extends Control
## Retro stage: emulator games rarely have a large image (hero), mostly just screenshots at 640 × 480
## or smaller. Stretched to full width and cropped, they turned blurry, zoomed in, a random section.
## Instead, the scene is shown uncropped in its own aspect ratio as a screen: scaled by an integer
## factor (pixels stay sharp, at most threefold), softly rounded, with a light shadow and a subtle
## sheen, without a frame. Behind it lies the cover, heavily blurred, as light - that part is done by
## whoever uses the stage (game page: game_page.gd, home page: background.gd). Several scenes can
## optionally cycle slowly (crossfade over T_LICHT); not with „Animationen reduzieren“ or in light mode.
##
## The rules (factor, size, position) are static and tested without a window: tests/logic_spielseite.gd
## and tests/logic_startseite.gd.

const U := preload("res://src/ui/u.gd")
const Leicht := preload("res://src/core/leicht.gd")

const MAX_FAKTOR := 3            ## höchstens so oft vergrößert (in Uzai-Punkten)
const PIXEL_MAX := 512           ## bis zu dieser Seitenlänge ein Pixelbild: Punkte bleiben hart
const WECHSEL_S := 9.0           ## so lange steht eine Szene, bevor die nächste überblendet
const SZENEN_MAX := 4            ## so viele Szenen wechseln höchstens durch

## Bildschirm: runde Ecken, zum Rand hin eine Spur dunkler (Wölbung), oben links ein ganz leiser
## Schein wie Licht auf Glas – kein Rand, keine Linien, keine Körnung.
const SCHIRM := """shader_type canvas_item;
uniform vec2 size = vec2(100.0);
uniform float radius = 12.0;
uniform float glanz = 1.0;
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
void fragment() {
	vec2 px = UV * size;
	vec2 q = min(px, size - px);
	float d = length(max(vec2(radius) - q, vec2(0.0))) - radius;
	vec4 c = texture(TEXTURE, UV);
	vec2 m = abs(UV - 0.5) * 2.0;
	float rand = smoothstep(0.62, 1.0, max(m.x, m.y));
	c.rgb *= 1.0 - 0.16 * glanz * rand;
	float s = clamp(1.0 - (UV.x * 0.55 + UV.y) * 1.25, 0.0, 1.0);
	c.rgb += vec3(0.055) * glanz * s * s;
	c.a *= clamp(0.5 - d, 0.0, 1.0);
	COLOR = c * tint;
}
"""

static var _shader: Shader


## Ein Shader für alle Bildschirme (nicht je Bild neu übersetzen).
static func schirm_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SCHIRM
	return _shader

## Szenen (Texture2D), die durchwechseln; die erste steht zuerst.
var szenen: Array = []
## Langsam durchwechseln (nur, wo die Bühne lange steht: Spielseite).
var wechseln := false
var _i := 0
var _box := Rect2()
var _unten := false
var _schirm: Control
var _uhr := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


# --- Regeln ------------------------------------------------------------------------------------

## Maßstab einer Szene (bild, in Bildpunkten der Datei) in der Fläche box (Uzai-Punkte); px:
## Bildpunkte je Uzai-Punkt (4K: 2). Passt sie mindestens einmal hinein, ganzzahlig in echten
## Bildpunkten (so bleibt jeder Pixel gleich groß), höchstens MAX_FAKTOR; ist sie größer als die
## Fläche, wird sie stufenlos verkleinert (nie beschnitten). 0, wenn es nichts zu zeigen gibt.
static func faktor(bild: Vector2i, box: Vector2, px := 1.0) -> float:
	if bild.x <= 0 or bild.y <= 0 or box.x <= 0.0 or box.y <= 0.0:
		return 0.0
	px = maxf(px, 0.01)
	var passt := minf(box.x * px / float(bild.x), box.y * px / float(bild.y))
	if passt < 1.0:
		return passt / px
	var n := mini(int(floor(passt + 0.0001)), maxi(1, int(floor(MAX_FAKTOR * px + 0.0001))))
	return float(n) / px


## Kleines Pixelbild (alte Systeme): hart vergrößern (TEXTURE_FILTER_NEAREST) statt weich.
static func pixelbild(bild: Vector2i) -> bool:
	return bild.x > 0 and bild.y > 0 and maxi(bild.x, bild.y) <= PIXEL_MAX


## Lage des Bildschirms in box: rechts bündig, senkrecht mittig (unten: auf der Unterkante), in
## ganzen Bildpunkten. Leer, wenn es nichts zu zeigen gibt.
static func schirm_rect(bild: Vector2i, box: Rect2, px := 1.0, unten := false) -> Rect2:
	var f := faktor(bild, box.size, px)
	if f <= 0.0:
		return Rect2()
	px = maxf(px, 0.01)
	var sz := (Vector2(bild) * f * px).round() / px
	var pos := Vector2(box.end.x - sz.x, box.end.y - sz.y if unten else box.position.y + (box.size.y - sz.y) * 0.5)
	return Rect2((pos * px).round() / px, sz)


# --- Zeigen ------------------------------------------------------------------------------------

## Szenen zeigen (die erste sofort, die weiteren wechseln durch, wenn wechseln an ist). box: Fläche
## in den Koordinaten dieses Knotens; unten: auf die Unterkante stellen. sofort: ohne Einblenden.
func zeigen(texs: Array, box: Rect2, unten := false, sofort := false) -> void:
	szenen = texs.filter(func(t: Variant) -> bool: return t is Texture2D).slice(0, SZENEN_MAX)
	_box = box
	_unten = unten
	_i = 0
	_uhr = 0.0
	if szenen.is_empty():
		weg()
		return
	_neu(szenen[0], sofort)
	_takt()


## Eine weitere Szene zum Durchwechseln (kommt sie später aus dem Netz).
func dazu(t: Texture2D) -> void:
	if t == null or szenen.has(t) or szenen.size() >= SZENEN_MAX:
		return
	szenen.append(t)
	_takt()


## Die Fläche hat sich geändert (Kopf der Spielseite neu gesetzt): Bildschirm an seinen Platz.
func platz(box: Rect2) -> void:
	_box = box
	if is_instance_valid(_schirm) and _i < szenen.size():
		_lege(_schirm, szenen[_i])


func zeigt() -> bool:
	return is_instance_valid(_schirm)


## Bühne leeren (anderes Bild, Spielstart): ausblenden.
func weg(sofort := false) -> void:
	szenen = []
	set_process(false)
	if not is_instance_valid(_schirm):
		return
	var alt := _schirm
	_schirm = null
	if sofort:
		alt.queue_free()
		return
	var tw := U.weg(alt, "uz_retro")
	tw.tween_property(alt, "modulate:a", 0.0, U.T_WEG)
	tw.finished.connect(alt.queue_free)


func _takt() -> void:
	set_process(wechseln and szenen.size() > 1 and not U.reduziert() and not Leicht.active)


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	_uhr += dt
	if _uhr < WECHSEL_S:
		return
	_uhr = 0.0
	_i = (_i + 1) % szenen.size()
	_neu(szenen[_i], false, U.T_LICHT)


## Neuer Bildschirm über dem alten: Er blendet auf, der alte geht danach (kein dunkles Loch).
## Ein anderes Spiel kommt im Takt eines Ortswechsels, das Durchwechseln ist Hintergrund (T_LICHT).
## Jeder Bildschirm blendet mit eigenem Tween: Geht er früher, endet sein Tween mit ihm.
func _neu(t: Texture2D, sofort: bool, dauer := U.T_ORT) -> void:
	var alt := _schirm
	var s := _Schirm.new()
	(s.bild.material as ShaderMaterial).shader = schirm_shader()
	add_child(s)
	_lege(s, t)
	_schirm = s
	if sofort:
		s.modulate.a = 1.0
		if is_instance_valid(alt):
			alt.queue_free()
		return
	s.modulate.a = 0.0
	s.create_tween().tween_property(s, "modulate:a", 1.0, dauer).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if is_instance_valid(alt):
		U.stop(alt, "uz_retro")
		var ta := alt.create_tween()
		ta.tween_interval(dauer)
		ta.tween_property(alt, "modulate:a", 0.0, U.T_WEG).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		ta.tween_callback(alt.queue_free)


func _lege(s: Control, t: Texture2D) -> void:
	var px := Media.px_scale() if is_inside_tree() else 1.0
	var bild := Vector2i(t.get_width(), t.get_height())
	var r := schirm_rect(bild, _box, px, _unten)
	s.position = r.position
	s.size = r.size
	(s as _Schirm).setze(t, faktor(bild, _box.size, px) >= 1.0 / px and pixelbild(bild))


## Ein Bildschirm: Schatten (im eigenen _draw, nie auf einem zuschneidenden Knoten), darauf die
## Szene mit runden Ecken und Glanz im Shader.
class _Schirm extends Control:
	var bild: TextureRect
	var _sb: StyleBoxFlat

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		bild = TextureRect.new()
		bild.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bild.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bild.stretch_mode = TextureRect.STRETCH_SCALE
		bild.set_anchors_preset(Control.PRESET_FULL_RECT)
		bild.material = ShaderMaterial.new()
		add_child(bild)
		resized.connect(func() -> void:
			(bild.material as ShaderMaterial).set_shader_parameter("size", size)
			queue_redraw()
		)

	func setze(t: Texture2D, hart: bool) -> void:
		bild.texture = t
		# Pixelbilder ganzzahlig vergrößert: jeder Punkt hart (keine Weichzeichnung, keine Treppen);
		# verkleinerte Bilder weich über Mipmaps, sonst glatt.
		bild.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if hart else CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var r := float(UzTheme.r_cover())
		var m := bild.material as ShaderMaterial
		m.set_shader_parameter("radius", r)
		m.set_shader_parameter("size", size)
		_sb = StyleBoxFlat.new()
		_sb.bg_color = Color(0, 0, 0, 1)
		_sb.set_corner_radius_all(int(r))
		_sb.anti_aliasing = true
		UzTheme.lift(_sb, 1)
		queue_redraw()

	func _draw() -> void:
		if _sb:
			draw_style_box(_sb, Rect2(Vector2.ZERO, size))

extends RefCounted
## Liquid Glass für das Mosaik (src/ui/layers/mosaik_seite.gd) – die eine, eng begrenzte Ausnahme von
## „kein Glas“ (docs/DESIGN.md › Mosaik: Liquid Glass). Kacheln sind Glasscheiben: dahinter weich
## unscharf der Raum bzw. der eigene Hintergrund, am Rand bricht die Scheibe ihn wie eine Linse,
## oben/links eine spiegelnde Lichtkante, die dem Fokus folgt (licht), dazu eine zarte Tönung.
##
## Leistung: Alle Scheiben einer Ebene zeichnet EIN Knoten (Unterlage) mit EINEM Material – die
## Screen-Texture wird so je Bild nur einmal kopiert (samt Unschärfe-Mipmaps), egal ob 4 oder 100
## Kacheln. Die Kacheln selbst (Bild, Glanz darüber) liegen darüber und lesen den Schirm nicht.
## Was eine Scheibe braucht, steht in der Eckfarbe (farbe()): r = Fokus 0…1, g = Rundung (Anteil der
## halben kurzen Seite), b = Stärke der Fensterkante (Glanz) bzw. bei Scheiben: dunkler getönt
## (Pillen mit Schrift), a = Deckkraft. Die Größe in echten
## Bildpunkten rechnet der Shader aus den Ableitungen von UV – darum in 4K genau so scharf.
##
## Einfach (ohne Brechung, ohne Screen-Texture): Kompatibel-Renderer bzw. Grafik „Kompatibel“,
## Animationen reduzieren, leichter Modus. Dann ist die Scheibe eine getönte, halb durchsichtige Fläche
## mit derselben Lichtkante.

const U := preload("res://src/ui/u.gd")
const Leicht := preload("res://src/core/leicht.gd")

## Gruppe der Kacheln, deren Scheibe die Unterlage zeichnet.
const GRUPPE := "uz_glas"

static var _scheibe_voll: ShaderMaterial
static var _scheibe_einfach: ShaderMaterial
static var _glanz: ShaderMaterial
static var _licht := Vector2(0.3, -0.25)

const _FORM := """
float kasten(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec2 kasten_n(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	vec2 n = (q.x > 0.0 && q.y > 0.0) ? normalize(q) : (q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
	return n * vec2(p.x < 0.0 ? -1.0 : 1.0, p.y < 0.0 ? -1.0 : 1.0);
}
"""

# Gemeinsamer Anfang: Form der Scheibe in echten Bildpunkten (px), Abstand zur Kante d (< 0 innen),
# Kanten-Normale n, Maßstab s gegenüber 1080p, Richtung zum Licht ld.
const _ANFANG := """
	vec4 par = COLOR;
	vec2 px = 1.0 / max(vec2(abs(dFdx(UV.x)), abs(dFdy(UV.y))), vec2(1e-5));
	float m = min(px.x, px.y);
	vec2 halb = px * 0.5;
	float r = clamp(par.g, 0.0, 1.0) * 0.5 * m;
	vec2 p = (UV - 0.5) * px;
	float d = kasten(p, halb, r);
	float maske = clamp(0.5 - d, 0.0, 1.0);
	vec2 n = kasten_n(p, halb, r);
	float s = max(1.0, 1.0 / (SCREEN_PIXEL_SIZE.y * 1080.0));
	vec2 mitte = SCREEN_UV - (UV - 0.5) * px * SCREEN_PIXEL_SIZE;
	vec2 ld = normalize((licht - mitte) / SCREEN_PIXEL_SIZE + vec2(0.001));
"""

# Lichtkante: innen an der Kante, hell auf der Seite zum Licht, schwach gegenüber; im Fokus breiter.
const _KANTE := """
	float kb = (1.4 + 1.4 * par.r) * s;
	float saum_k = clamp(1.0 + (d + 0.5) / kb, 0.0, 1.0);
	saum_k *= saum_k;
	float zu = max(dot(n, ld), 0.0);
	float gegen = max(-dot(n, ld), 0.0);
	float glanz = saum_k * (0.16 + 0.72 * zu * zu + 0.3 * gegen * gegen * gegen) * (0.8 + 0.7 * par.r);
"""


static func _voll_code() -> String:
	return """shader_type canvas_item;
render_mode blend_mix;
// Liquid Glass (src/ui/components/glas.gd): Brechung am Rand, Unschärfe dahinter, Lichtkante.
uniform sampler2D schirm : hint_screen_texture, filter_linear_mipmap;
uniform vec2 licht = vec2(0.3, -0.25);
uniform float unschaerfe = 2.6;
uniform float brechung = 1.0;
uniform vec4 toenung : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float toenung_k = 0.08;
""" + _FORM + """
void fragment() {
""" + _ANFANG + """
	float band = clamp(m * 0.18, 5.0 * s, 30.0 * s);
	float e = clamp(1.0 + d / band, 0.0, 1.0);
	float bieg = e * e * e;
	// Zum Rand hin holt die Scheibe den Hintergrund nach innen (Linse), insgesamt leicht gewölbt.
	vec2 off = -n * bieg * band * 0.65 * brechung - p * 0.035 * brechung;
	vec2 uv = SCREEN_UV + off * SCREEN_PIXEL_SIZE;
	vec2 fs = n * bieg * 2.2 * s * brechung * SCREEN_PIXEL_SIZE;
	float lod = unschaerfe + log2(s) + e * 0.8;
	vec3 c = vec3(textureLod(schirm, uv + fs, lod).r, textureLod(schirm, uv, lod).g, textureLod(schirm, uv - fs, lod).b);
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = max(mix(vec3(l), c, 1.3), vec3(0.0));
	c = mix(c, toenung.rgb, toenung_k) + 0.03 + 0.045 * par.r;
	c += vec3(0.09) * e * e;
	c *= 1.0 - 0.5 * par.b;
""" + _KANTE + """
	c = mix(c, vec3(1.0), clamp(glanz, 0.0, 1.0));
	COLOR = vec4(c, maske * par.a);
}
"""


static func _einfach_code() -> String:
	return """shader_type canvas_item;
render_mode blend_mix;
// Liquid Glass, einfache Fassung (src/ui/components/glas.gd): getönt, ohne Screen-Texture.
uniform vec2 licht = vec2(0.3, -0.25);
uniform vec4 basis : source_color = vec4(0.13, 0.14, 0.16, 0.62);
""" + _FORM + """
void fragment() {
""" + _ANFANG + """
	float band = clamp(m * 0.18, 5.0 * s, 30.0 * s);
	float e = clamp(1.0 + d / band, 0.0, 1.0);
	vec3 c = (basis.rgb + (1.0 - UV.y) * 0.05 + 0.05 * par.r + vec3(0.08) * e * e) * (1.0 - 0.4 * par.b);
	float a = basis.a + 0.25 * par.b;
""" + _KANTE + """
	c = mix(c, vec3(1.0), clamp(glanz, 0.0, 1.0));
	a = max(a, clamp(glanz, 0.0, 1.0));
	COLOR = vec4(c, a * maske * par.a);
}
"""


static func _glanz_code() -> String:
	return """shader_type canvas_item;
render_mode blend_mix;
// Glanz über dem Bild einer Glaskachel (src/ui/components/glas.gd): ein breiter weicher Schimmer,
// der beim Fokus über die Scheibe wandert, oben etwas Licht, am Fensterrand eine feine Vertiefung.
uniform vec2 licht = vec2(0.3, -0.25);
""" + _FORM + """
void fragment() {
""" + _ANFANG + """
	float t = par.r;
	float diag = dot(UV - 0.5, normalize(vec2(0.55, 1.0)));
	float pos = mix(-0.78, -0.16, t) + clamp(ld.x, -1.0, 1.0) * 0.05;
	float w = (diag - pos) / 0.17;
	float hell = exp(-w * w) * (0.05 + 0.11 * t) + pow(1.0 - UV.y, 4.0) * 0.07;
	float innen = clamp(1.0 + d / (4.0 * s), 0.0, 1.0);
	float dunkel = innen * innen * 0.34 * par.b;
""" + _KANTE + """
	hell += glanz * 0.55 * par.b;
	float a = clamp(hell + dunkel, 0.0, 1.0);
	COLOR = vec4(vec3(hell / max(hell + dunkel, 0.0001)), a * maske * par.a);
}
"""


## Ohne Brechung? (siehe Kopf)
static func einfach() -> bool:
	if Leicht.active or U.reduziert():
		return true
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return true
	return str(Config.get_value("system.grafik", "realistisch")) == "kompatibel"


static func _material(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("licht", _licht)
	return mat


## Material der Scheiben (eines für alle).
static func scheibe() -> ShaderMaterial:
	if einfach():
		if _scheibe_einfach == null:
			_scheibe_einfach = _material(_einfach_code())
		var b: Color = UzTheme.col("surface_hi")
		_scheibe_einfach.set_shader_parameter("basis", Color(b, 0.62))
		return _scheibe_einfach
	if _scheibe_voll == null:
		_scheibe_voll = _material(_voll_code())
	return _scheibe_voll


## Material des Glanzes über Bildern (eines für alle, liest den Schirm nicht).
static func glanz() -> ShaderMaterial:
	if _glanz == null:
		_glanz = _material(_glanz_code())
	return _glanz


## Eckfarbe einer Scheibe: Fokus, Rundung (Halbmesser in Punkten), Fensterkante, Deckkraft.
static func farbe(fokus: float, radius: float, groesse: Vector2, kante := 0.0, a := 1.0) -> Color:
	var m := maxf(1.0, minf(groesse.x, groesse.y))
	return Color(clampf(fokus, 0.0, 1.0), clampf(radius * 2.0 / m, 0.0, 1.0), clampf(kante, 0.0, 1.0), clampf(a, 0.0, 1.0))


## Wo das Licht steht (in Bildschirm-Anteilen, 0…1; außerhalb erlaubt): alle Lichtkanten richten
## sich danach.
static func licht(uv: Vector2) -> void:
	_licht = uv
	for mat in [_scheibe_voll, _scheibe_einfach, _glanz]:
		if mat:
			(mat as ShaderMaterial).set_shader_parameter("licht", uv)


static var _licht_tw: Tween


## Licht weich zu einem neuen Platz ziehen (im Takt, T_ORT); n trägt die Bewegung.
static func licht_zu(n: Node, ziel: Vector2) -> void:
	if _licht_tw and _licht_tw.is_valid():
		_licht_tw.kill()
	if U.reduziert() or not n.is_inside_tree():
		licht(ziel)
		return
	_licht_tw = U.ankommen(n, U.T_ORT, "mz_licht")
	_licht_tw.tween_method(func(v: Vector2) -> void: licht(v), _licht, ziel, U.T_ORT)

extends Control
## Hintergrund: ein sehr dunkler Raum mit weichen Farbverläufen (drei große Lichter in der Farbe
## des gewählten Spiels und seinen Nachbarfarben), die ganz langsam wandern. Darüber steht das
## Bild des Spiels scharf oben rechts (ab 0.9, wie auf aktuellen Konsolen): Es läuft nach links
## und unten in weichen Verläufen in den Raum aus, oben ist es für die Leiste zurückgenommen.
## Kein bildschirmgroßer Weichzeichner mehr – nur ein Cover ohne großes Bild leuchtet leicht
## weich an derselben Stelle. Andere Arten: eigenes Bild (ganzer Schirm), nur Farbe, "Nebel".
## Die Grundwerte des Aussehens (UzTheme.bg_param) legen fest, wo das Bild steht und wie es
## ausläuft und wie stark die Lichter und die Spielfarbe sind.

var _a: TextureRect
var _b: TextureRect
## Lichter, beide Abdunklungen und das Rauschen in einer Ebene (ROOM). Früher waren das sechs
## Vollbild-Ebenen übereinander; jede mischte den ganzen Schirm (4K: je 8 Mio. Punkte lesen und
## schreiben). Der Shader mischt sie in derselben Reihenfolge, mathematisch gleich.
var _room: ColorRect
var _room_mat: ShaderMaterial
var _dim := 0.55
var _front := 0
var _current := ""
var _motes: Array = []
var _mode := "game"
var _blur_mat: ShaderMaterial
var _ground := Color(0, 0, 0)
var _ground_tw: Tween
var _tint_key := ""
var _blobs: Array = []          ## { at (Anteil), size (Anteil), amp, per, ph, a, depth }
var _aur_tw: Tween
var _aur_t := 0.0
var _aur_cols: Array = [Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]
var _pan := 0.0                 ## seitlicher Schwenk der Lichter (je Bereich ein Stück)
var _pan_tw: Tween
var _last_input := 0            ## letzte Eingabe (ms): danach ruhen die Lichter langsamer
## Retro-Bühne (Startseite, Emulator-Spiele ohne Hero): die Spielszene als Bildschirm oben rechts
## über dem weichen Licht aus dem Cover (retro_buehne.gd). Gehört zu dem Bild mit _retro_key.
var _retro: Control
var _retro_key := ""

const MediaS := preload("res://src/core/media.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Zuschnitt := preload("res://src/core/zuschnitt.gd")
const U := preload("res://src/ui/u.gd")
const RetroBuehne := preload("res://src/ui/components/retro_buehne.gd")
## Bildwechsel: kurz überblenden. Unbekannte Bilder erst laden, wenn die Auswahl kurz ruht
## (beim Halten des Steuerkreuzes nicht pro Schritt); schon geladene und vorab geladene
## (Nachbarn im Regal, siehe prefetch) kommen sofort.
const FADE_S := 0.28
const DWELL := 0.1
## Feinheit des leichten Weichzeichners für Cover und kleine Spielszenen (Media.soft).
const COVER_STEPS := 40
const SHOT_STEPS := 150
## Das Bild im Raum, in einem Zug: scharf (oder leicht weich), nach links und unten durchsichtig
## (sanfte Kurven, keine Kante), oben zur Leiste hin etwas dunkler, dazu ±1 Stufe Rauschen gegen
## Streifen (U.ENTSTUFEN_GLSL, vormultipliziert nach dem Mischen gerechnet: Es wirkt auch dort, wo
## das Bild schon fast ausgelaufen ist). mask = 0: eigenes Bild über den ganzen Schirm ohne Verläufe
## (Art "bild").
const HERO := """shader_type canvas_item;
render_mode blend_premul_alpha;
""" + U.ENTSTUFEN_GLSL + """
uniform vec2 stage = vec2(1382.0, 734.0);
uniform float mask = 1.0;
uniform float shade = 0.0;
uniform float top_dim = 0.0;
uniform float lod = 0.0;
uniform float radius = 0.0;
uniform int taps = 12;
uniform float fade_x = 0.58;     // so weit läuft das Bild nach links aus (Anteil), 0 = gar nicht
uniform float fade_y = 0.4;      // ab hier läuft es nach unten aus
uniform float grade = 1.0;       // filmische Farbe (0 = das Bild, wie es ist; leichter Modus)
uniform float zoom = 1.0;        // > 1: näher dran (das neue Bild setzt sich beim Wechsel)
uniform vec2 zoom_at = vec2(0.62, 0.38);
varying vec2 local;
varying vec4 tint;
void vertex() {
	local = VERTEX / stage;
	// Farbe der Fläche samt modulate: Ohne sie wirkte die Deckkraft nicht – die Überblendung
	// sprang von unsichtbar auf voll (wie zwei Bilder pro Sekunde).
	tint = COLOR;
}
void fragment() {
	vec4 c;
	vec2 uv = (UV - zoom_at) / zoom + zoom_at;
	if (radius > 0.0) {
		c = vec4(0.0);
		float ws = 0.0;
		for (int i = 0; i < taps; i++) {
			float f = (float(i) + 0.5) / float(taps);
			float a = float(i) * 2.39996;
			vec2 o = vec2(cos(a), sin(a)) * sqrt(f) * radius;
			float w = exp(-f * 2.2);
			c += textureLod(TEXTURE, clamp(uv + o, vec2(0.002), vec2(0.998)), lod) * w;
			ws += w;
		}
		c /= ws;
	} else if (lod > 0.0) {
		c = textureLod(TEXTURE, uv, lod);
	} else {
		c = texture(TEXTURE, uv);
	}
	// Filmische Farbe, sehr leicht: eine sanfte S-Kurve (Tiefe), etwas mehr Farbe in den Mitten,
	// Schatten eine Spur kühler, Lichter eine Spur wärmer.
	if (grade > 0.0) {
		vec3 g = clamp(c.rgb, 0.0, 1.0);
		float lum = dot(g, vec3(0.2126, 0.7152, 0.0722));
		g = mix(g, g * g * (3.0 - 2.0 * g), 0.2 * grade);
		g = mix(vec3(lum), g, 1.0 + 0.12 * grade * (1.0 - abs(lum - 0.5) * 2.0));
		g += grade * vec3(-0.012, -0.002, 0.016) * (1.0 - smoothstep(0.0, 0.45, lum));
		g += grade * vec3(0.014, 0.006, -0.01) * smoothstep(0.55, 1.0, lum);
		c.rgb = clamp(g, 0.0, 1.0);
	}
	float x = clamp(local.x, 0.0, 1.0);
	float y = clamp(local.y, 0.0, 1.0);
	float l = fade_x > 0.001 ? smoothstep(0.0, fade_x, x) : 1.0;
	l = l * l * (1.6 - 0.6 * l);
	float b = 1.0 - smoothstep(fade_y, 1.0, y);
	b = b * (1.15 - 0.15 * b);
	float a = mix(1.0, clamp(l * b, 0.0, 1.0), mask);
	float top = mix(1.0 - top_dim, 1.0, smoothstep(0.0, 0.34, y));
	float edge = 1.0 - 0.18 * smoothstep(0.82, 1.0, x);
	// Eine feine Vignette um die Mitte des Bilds (nur Spielbild).
	float vig = 1.0 - 0.14 * grade * smoothstep(0.45, 1.05, length((vec2(x, y) - vec2(0.6, 0.45)) * vec2(1.0, 1.25)));
	vec3 rgb = c.rgb * mix(1.0, top * edge * vig * (1.0 - shade), mask);
	vec4 o = vec4(rgb, c.a * a) * tint;
	COLOR = vec4(o.rgb * o.a + uz_rauschen(FRAGCOORD.xy) * step(0.0005, o.a), o.a);
}
"""
## So weit schwenken die Lichter je Bereich (px). Klein genug, dass es nur als Raum spürbar ist.
const PAN_STEP := 34.0
## Der Raum über dem Bild in einem Zug, in dieser Reihenfolge übereinander gemischt:
## drei weiche Lichter (runde Verläufe, eingefärbt), die Abdunklung von unten und von links in
## der Raumfarbe und zuletzt ein unsichtbares Rauschen von ±1 Stufe gegen Stufen in dunklen
## Verläufen (8-Bit-Fernseher, U.ENTSTUFEN_GLSL: blau verteilt, nach dem Mischen gerechnet – so
## bricht es die Ringe der Lichter auch dort, wo sie fast durchsichtig sind). Ergebnis wie die
## früheren sechs Ebenen: Jede Schicht wird wie beim normalen Mischen „über“ das Bisherige gelegt
## (vormultipliziert gerechnet).
const ROOM := """shader_type canvas_item;
render_mode blend_premul_alpha;
""" + U.ENTSTUFEN_GLSL + """
uniform vec2 view = vec2(1920.0, 1080.0);
uniform vec4 ground = vec4(0.0, 0.0, 0.0, 1.0);
uniform float dim = 0.55;
uniform vec4 r0; uniform vec4 r1; uniform vec4 r2;
uniform vec4 c0; uniform vec4 c1; uniform vec4 c2;
float ramp(float t, vec4 o, vec4 v) {
	t = clamp(t, 0.0, 1.0);
	if (t <= o.y) return mix(v.x, v.y, (t - o.x) / max(o.y - o.x, 1e-5));
	if (t <= o.z) return mix(v.y, v.z, (t - o.y) / max(o.z - o.y, 1e-5));
	return mix(v.z, v.w, (t - o.z) / max(o.w - o.z, 1e-5));
}
float blob(vec2 p, vec4 r) {
	if (r.z <= 0.0 || r.w <= 0.0) return 0.0;
	vec2 q = (p - r.xy) / r.zw - 0.5;
	return ramp(length(q) / 0.5, vec4(0.0, 0.35, 0.7, 1.0), vec4(1.0, 0.62, 0.18, 0.0));
}
void over(inout vec3 acc, inout float a, vec3 c, float s) {
	acc = c * s + acc * (1.0 - s);
	a = s + a * (1.0 - s);
}
void fragment() {
	vec2 p = UV * view;
	vec3 acc = vec3(0.0);
	float a = 0.0;
	over(acc, a, c0.rgb, blob(p, r0) * c0.a);
	over(acc, a, c1.rgb, blob(p, r1) * c1.a);
	over(acc, a, c2.rgb, blob(p, r2) * c2.a);
	float from_bottom = 1.0 - UV.y;
	float sb = ramp(from_bottom, vec4(0.0, 0.22, 0.48, 1.0), vec4(1.0, 0.94, min(1.0, dim + 0.12), dim * 0.2));
	float sl = ramp(UV.x, vec4(0.0, 0.5, 0.5, 1.0), vec4(min(1.0, dim + 0.1), dim * 0.25, dim * 0.25, dim * 0.5));
	over(acc, a, ground.rgb, sb);
	over(acc, a, ground.rgb, sl);
	// Samt modulate (COLOR: Farbe der Fläche · modulate): Der Aufbau der Startseite lässt das Licht
	// so aufgehen; sonst steht modulate auf Weiß und ändert nichts.
	vec4 o = vec4(acc / max(a, 1e-5), a) * COLOR;
	COLOR = vec4(o.rgb * o.a + uz_rauschen(FRAGCOORD.xy) * step(0.0005, o.a), o.a);
}
"""
## Weichzeichner: eine Spirale aus 12 Proben, gewichtet wie eine Glocke, dazu ein Hauch Rauschen
## gegen Stufen. Früher stand hier nur eine sehr grobe Mipmap-Stufe – das sah auf großen
## Bildschirmen blockig aus. Danach waren es 32 Proben pro Bildpunkt in jedem Bild (Hintergrund,
## Spielseite, Guide über dem Spiel); im Bildvergleich sehen 12 gleich aus und kosten ein Drittel.
const BLUR := """shader_type canvas_item;
uniform float lod = 0.0;
uniform float radius = 0.0;
uniform int taps = 12;
uniform float dither = 0.0;
varying vec4 tint;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void vertex() {
	tint = COLOR;
}
void fragment() {
	if (radius <= 0.0) {
		COLOR = textureLod(TEXTURE, UV, lod);
		COLOR.rgb += (hash(FRAGCOORD.xy) - 0.5) / 255.0 * dither;
		COLOR *= tint;
	} else {
		vec4 acc = vec4(0.0);
		float ws = 0.0;
		for (int i = 0; i < taps; i++) {
			float f = (float(i) + 0.5) / float(taps);
			float a = float(i) * 2.39996;
			vec2 o = vec2(cos(a), sin(a)) * sqrt(f) * radius;
			float w = exp(-f * 2.2);
			acc += textureLod(TEXTURE, clamp(UV + o, vec2(0.002), vec2(0.998)), lod) * w;
			ws += w;
		}
		COLOR = acc / ws;
		COLOR.rgb += (hash(FRAGCOORD.xy) - 0.5) / 160.0;
		COLOR *= tint;
	}
}
"""

## Proben je Bildpunkt im Weichzeichner (HERO, BLUR): 12, im leichten Modus 4. Die Bilder sind
## vorher schon klein gerechnet (Media.soft), der Shader glättet nur noch – mit 4 Proben kaum anders.
static func blur_taps() -> int:
	return Leicht.BLUR_TAPS if Leicht.active else 12


## Stärke des Weichzeichners zu einer Stufe (alte Werte 0…5 bleiben gültig).
static func blur_params(level: float) -> Vector2:
	if level <= 0.0:
		return Vector2.ZERO
	return Vector2(minf(level * 0.5, 2.2), clampf(level * 0.012, 0.0, 0.06))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = HERO
	_blur_mat.shader = sh
	# Filmische Farbe und Vignette nur mit vollem Bild (leichter Modus: das Bild, wie es ist).
	_blur_mat.set_shader_parameter("grade", 0.0 if Leicht.active else 1.0)
	_a = _make_layer()
	_b = _make_layer()
	_retro = RetroBuehne.new()
	_retro.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_retro)
	# Farbverläufe über dem Bild, unter den Abdunklungen. "depth": wie stark ein Licht beim
	# Bereichswechsel mitschwenkt (verschieden stark – das gibt Tiefe).
	var spots := [
		{ "at": Vector2(0.3, -0.04), "size": Vector2(1.35, 1.05), "amp": Vector2(80, 36), "per": 23.0, "ph": 0.0, "a": 0.66, "depth": 1.0 },
		{ "at": Vector2(0.86, 0.04), "size": Vector2(1.05, 0.9), "amp": Vector2(60, 44), "per": 31.0, "ph": 1.7, "a": 0.5, "depth": 0.6 },
		{ "at": Vector2(0.56, 0.4), "size": Vector2(1.0, 0.62), "amp": Vector2(96, 28), "per": 19.0, "ph": 3.1, "a": 0.26, "depth": 1.5 },
	]
	_blobs = spots
	# Lichter, Abdunklungen (das Bild läuft zum Raum hin aus) und Rauschen: eine Ebene.
	_room = ColorRect.new()
	_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room.set_anchors_preset(Control.PRESET_FULL_RECT)
	_room_mat = ShaderMaterial.new()
	var rs := Shader.new()
	rs.code = ROOM
	_room_mat.shader = rs
	_room.material = _room_mat
	add_child(_room)
	for i in 46:
		_motes.append({ "p": Vector2(randf(), randf()), "v": 0.004 + randf() * 0.01, "r": 1.0 + randf() * 2.4, "a": 0.15 + randf() * 0.45, "ph": randf() * TAU })
	_ground = UzTheme.col("bg")
	apply_theme()
	UzTheme.rebuilt.connect(apply_theme)


## Aufbau der Startseite (startseite_aufbau.gd): Licht und Raum (raum) und das große Bild (bild)
## gehen getrennt auf, je 0…1. Über self_modulate – die Überblendung der Bilder (_show) arbeitet
## mit modulate und bleibt davon unberührt. Darunter steht schon der Grund (_draw).
func aufbau(raum: float, bild: float) -> void:
	if is_instance_valid(_room):
		_room.self_modulate.a = raum
	for t in [_a, _b]:
		if is_instance_valid(t):
			(t as CanvasItem).self_modulate.a = bild
	if is_instance_valid(_retro):
		_retro.modulate.a = bild


## Farben der Lichter aus einer Grundfarbe: die Farbe selbst und zwei Nachbarn.
static func aurora_from(c: Color) -> Array:
	var h := c.h
	var s := c.s
	if s < 0.12:
		# Ohne kräftige Farbe: warmes Graphit-Gold, zurückhaltend.
		h = 0.1
		s = 0.3
	if UzTheme.light:
		return [Color.from_hsv(h, clampf(s * 0.5, 0.18, 0.4), 0.98), Color.from_hsv(fposmod(h + 0.09, 1.0), clampf(s * 0.45, 0.15, 0.35), 0.96),
				Color.from_hsv(fposmod(h - 0.07, 1.0), clampf(s * 0.4, 0.12, 0.3), 0.95)]
	return [Color.from_hsv(h, clampf(s * 1.05, 0.45, 0.82), 0.78), Color.from_hsv(fposmod(h + 0.09, 1.0), clampf(s * 0.95, 0.4, 0.78), 0.66),
			Color.from_hsv(fposmod(h - 0.07, 1.0), clampf(s * 0.85, 0.35, 0.72), 0.58)]


func _set_aurora(c: Color, instant := false) -> void:
	var target := aurora_from(c)
	if _aur_tw:
		_aur_tw.kill()
	if instant:
		_aur_cols = target
		_place_blobs()
		return
	var from := _aur_cols.duplicate()
	_aur_tw = create_tween()
	_aur_tw.tween_method(func(v: float) -> void:
		for i in 3:
			_aur_cols[i] = (from[i] as Color).lerp(target[i], v)
		_place_blobs()
	, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Lage und Farbe der Lichter; sie wandern ganz langsam und atmen ein wenig. (Rechteck und
## Farbe gehen an den ROOM-Shader; ein Licht ist ein runder Verlauf über sein Rechteck.)
func _place_blobs() -> void:
	if _room_mat == null:
		return
	var vs := size if size.x > 0 else Vector2(1920, 1080)
	_room_mat.set_shader_parameter("view", vs)
	var on := _aurora_on()
	for i in _blobs.size():
		var b: Dictionary = _blobs[i]
		if not on:
			_room_mat.set_shader_parameter("c%d" % i, Color(0, 0, 0, 0))
			continue
		var sz: Vector2 = vs * (b.size as Vector2)
		var w := TAU * _aur_t / float(b.per)
		var off := Vector2(sin(w + b.ph) * b.amp.x + _pan * float(b.get("depth", 1.0)), cos(w * 0.8 + b.ph) * b.amp.y)
		var pos: Vector2 = vs * (b.at as Vector2) - sz * 0.5 + off
		_room_mat.set_shader_parameter("r%d" % i, Vector4(pos.x, pos.y, sz.x, sz.y))
		var col: Color = _aur_cols[i]
		var breath := 0.9 + 0.1 * sin(w * 1.3 + b.ph)
		var light_k := 0.55 if UzTheme.light else 1.0
		_room_mat.set_shader_parameter("c%d" % i, Color(col.r, col.g, col.b, float(b.a) * breath * light_k * _aurora_k()))


## Bereichswechsel: die Lichter schwenken langsam ein Stück zur Seite, als ginge man in den
## nächsten Raum (Bereich index von count; die Mitte steht still).
func pan_to(index: int, count: int) -> void:
	if index < 0 or count <= 0:
		return
	var target := pan_offset(index, count)
	if _pan_tw:
		_pan_tw.kill()
	_pan_tw = create_tween()
	_pan_tw.tween_property(self, "_pan", target, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


static func pan_offset(index: int, count: int) -> float:
	return -(float(index) - (float(count) - 1.0) * 0.5) * PAN_STEP


func _aurora_on() -> bool:
	return _mode in ["game", "nebel", "farbe"] and _aurora_k() > 0.01


## Stärke der Farbverläufe: Einstellung mal Grundwert.
func _aurora_k() -> float:
	return float(Config.get_value("theme.aurora", 1.0)) * float(UzTheme.bg_param("aurora"))


## The game image uses only this share of its area's height (top-aligned, the mask fades out inside it):
## wide heroes (3 : 1) filled the full height only when heavily enlarged and cropped at the sides, which
## looked slightly too close. The tabs and covers sit below it anyway.
const BILD_H := 0.86


## Fläche des Spielbilds (Anteile des Schirms): rechts oben, gut zwei Drittel hoch.
static func stage_rect() -> Rect2:
	var st: Array = UzTheme.bg_param("stage")
	return Rect2(float(st[0]), float(st[1]), float(st[2]), float(st[3]))


func _make_layer() -> TextureRect:
	var t := TextureRect.new()
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.modulate.a = 0.0
	t.material = _blur_mat.duplicate()
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.resized.connect(func() -> void: (t.material as ShaderMaterial).set_shader_parameter("stage", t.size))
	add_child(t)
	return t


## Ebenen je nach Art: Spielbild oben rechts über dem Raum (die Lichter scheinen in den Verläufen
## durch), eigenes Bild über den ganzen Schirm unter dem Raum (dessen Abdunklung hält Text lesbar).
func _arrange() -> void:
	var stage := _mode == "game"
	var sr := stage_rect()
	for t in [_a, _b]:
		var l := t as TextureRect
		l.anchor_left = sr.position.x if stage else 0.0
		l.anchor_top = sr.position.y if stage else 0.0
		l.anchor_right = sr.end.x if stage else 1.0
		l.anchor_bottom = (sr.position.y + sr.size.y * BILD_H) if stage else 1.0
		l.offset_left = 0
		l.offset_top = 0
		l.offset_right = 0
		l.offset_bottom = 0
		var m := l.material as ShaderMaterial
		m.set_shader_parameter("mask", 1.0 if stage else 0.0)
		m.set_shader_parameter("shade", 0.0 if UzTheme.light else _dim * float(UzTheme.bg_param("shade")))
		m.set_shader_parameter("top_dim", 0.0 if UzTheme.light else float(UzTheme.bg_param("top_dim")))
		m.set_shader_parameter("fade_x", float(UzTheme.bg_param("fade_x")))
		m.set_shader_parameter("fade_y", float(UzTheme.bg_param("fade_y")))
	move_child(_room, 0)
	if not stage:
		move_child(_room, maxi(_a.get_index(), _b.get_index()))
	# Der Bildschirm der Retro-Bühne liegt über allem (Licht, Bild); nur im Spielbild-Modus.
	if is_instance_valid(_retro):
		move_child(_retro, -1)
		if not stage:
			_retro.weg(true)


func apply_theme() -> void:
	_mode = UzTheme.bg_mode()
	# Abdunklung von unten (ab etwa der Mitte deckt der Raum alles ab, dort liegen Reiter und
	# Cover) und von links (dort steht der Titel); Verläufe im ROOM-Shader.
	_dim = clampf(float(Config.get_value("theme.dim", 0.55)), 0.0, 0.95)
	_room_mat.set_shader_parameter("dim", _dim)
	_arrange()
	if not tint_on():
		_set_ground(UzTheme.col("bg"), true)
	else:
		_room_mat.set_shader_parameter("ground", _ground)
	_set_aurora(_ground if tint_on() else UzTheme.col("accent"), true)
	if _mode == "bild":
		var file := str(Config.get_value("theme.background_image", ""))
		if file != "" and FileAccess.file_exists(file):
			_current = ""
			Media.file_texture(file, 1920, func(t: Texture2D) -> void: _show(t, "user:" + file, 0.0))
	elif _mode != "game":
		_show(null, "", 0.0)
	queue_redraw()


## Aktuelle Raumfarbe (für den Lichtschein im Guide).
func ground() -> Color:
	return _ground


func tint_on() -> bool:
	return bool(Config.get_value("theme.tint", true)) and bool(UzTheme.bg_param("tint")) and (_mode == "game" or _mode == "nebel")


## Bild zum fokussierten Spiel: das große Bild (Hero) scharf; ohne Hero eine Spielszene leicht
## weich (alte Systeme haben nur kleine), sonst das Cover leicht weich und zurückgenommen.
## soft (Startseite): das Bild weich als Hintergrund – oben rechts liegen dort „Für dich“-Kacheln,
## ein scharfes Bild dahinter wäre unruhig (Marke, Regel 4: Blur ist Hintergrund).
var _dwell_id := 0
## Weichheit des Hintergrunds der Startseite (Media.soft, etwa 48 px Unschärfe in 1080p) und
## wie weit er durchscheint.
const HOME_STEPS := 22
const HOME_LEVEL := 0.82


func show_game(game: Dictionary, soft := false, buehne := false) -> void:
	# Beim Spielstart steht das Bild vorn (nach_vorn): bis zurueck() kein anderes.
	if _mode != "game" or game.is_empty() or vorn:
		return
	var key := ("soft:" if soft else "") + ("retro:" if buehne else "") + str(game.get("id", ""))
	if key == _current:
		return
	_current = key
	_dwell_id += 1
	var my := _dwell_id
	if soft:
		_show_home(game, key, my)
		return
	var area := fit_size()
	# Schon geladen oder schon unterwegs (zurückblättern, vorab geladene Nachbarn, Spielseite):
	# sofort. Sonst erst, wenn die Auswahl kurz ruht – beim Halten kein Laden pro Schritt.
	var hp := Media.local_path(game, "hero")
	if not Media.has_fit(hp, area):
		await get_tree().create_timer(DWELL).timeout
		if my != _dwell_id or key != _current:
			return
	Media.urgent_fit(hp, area)
	var instant := Media.cached_fit(hp, area)
	if instant:
		tint_game(game)
		_show(instant, key, 0.0, 1.0)
		return
	Media.game_file(game, "hero", func(path: String) -> void:
		if key != _current:
			return
		if path == "":
			tint_game(game)
			_show_fallback(game, key, buehne)
			return
		Media.fit_texture(path, area, func(t: Texture2D) -> void:
			if key != _current:
				return
			if t == null:
				tint_game(game)
				_show_fallback(game, key, buehne)
				return
			# Frisch hochgeladen: erst ein Bild später überblenden. Was der Treiber beim ersten
			# Zeichnen noch nachholt, fällt so nicht in die Überblendung.
			await get_tree().process_frame
			if key != _current:
				return
			# Farbe und Bild wechseln zusammen – vorher kam erst die Raumfarbe, dann das Bild
			# (zwei Sprünge statt eines Übergangs).
			tint_game(game)
			_show(t, key, 0.0, 1.0)
		)
	)


## Startseite: das große Bild klein gerechnet und weich (Hilfsthread, winzige Textur – kein
## Hochladen eines großen Bilds beim Blättern); ohne Hero das Cover, ebenso weich.
func _show_home(game: Dictionary, key: String, my: int) -> void:
	if not Media.has_soft(Media.local_path(game, "hero"), HOME_STEPS):
		await get_tree().create_timer(DWELL).timeout
		if my != _dwell_id or key != _current:
			return
	tint_game(game)
	Media.game_soft(game, "hero", HOME_STEPS, func(t: Texture2D) -> void:
		if key != _current:
			return
		if t:
			_show(t, key, -soft_radius(HOME_STEPS), HOME_LEVEL)
			return
		Media.game_soft(game, "cover", HOME_STEPS, func(c: Texture2D) -> void:
			if key == _current:
				_show(c, key, -soft_radius(HOME_STEPS), 0.6)
		)
	)


## Ohne Hero: Spielszene (Emulator-Spiele) bzw. Cover, leicht weich. buehne (Startseite): Eine
## große, breite Szene (hero_tauglich) steht scharf wie ein Hero; jede andere ungeschnitten als
## Bildschirm auf der Retro-Bühne vor dem weichen Cover – nie gestreckt, nie beschnitten.
func _show_fallback(game: Dictionary, key: String, buehne := false) -> void:
	var shot := Media.local_path(game, "shot") if game.get("source") in ["rom", "disc"] else ""
	if shot != "" and buehne:
		# Schon geladene Spielszene (nur aus dem Cache, beim Blättern nichts nachladen).
		Media.file_texture(shot, Media.max_width("shot"), func(sh: Texture2D) -> void:
			if key != _current:
				return
			if sh == null:
				_show_cover(game, key)
			elif MediaS.hero_tauglich(MediaS.orig_groesse(sh)):
				Media.fit_texture(shot, fit_size(), func(t: Texture2D) -> void:
					if key == _current:
						_show(t if t else sh, key, 0.0, 1.0)
				)
			else:
				_show_retro(game, key, sh)
		)
	elif shot != "" and game.get("source") == "rom":
		Media.game_soft(game, "shot", SHOT_STEPS, func(sh: Texture2D) -> void:
			if key == _current:
				_show(sh, key, -soft_radius(SHOT_STEPS), 0.9)
		)
	else:
		_show_cover(game, key)


func _show_cover(game: Dictionary, key: String) -> void:
	Media.game_soft(game, "cover", COVER_STEPS, func(c: Texture2D) -> void:
		if key == _current:
			_show(c, key, -soft_radius(COVER_STEPS), 0.6)
	)


## Wie hell das Licht hinter der Retro-Bühne steht (das weiche Cover; ohne Cover die Szene).
const RETRO_LICHT := 0.72


## Retro-Bühne: erst das Licht (Cover weich, sonst die Szene weich), dann im selben Bild der
## Bildschirm – Licht und Szene kommen zusammen, nicht nacheinander.
func _show_retro(game: Dictionary, key: String, sh: Texture2D) -> void:
	Media.game_soft(game, "cover", COVER_STEPS, func(c: Texture2D) -> void:
		if key != _current:
			return
		if c:
			_retro_mit(key, sh, c, COVER_STEPS)
		else:
			Media.soft(sh, COVER_STEPS, func(s2: Texture2D) -> void:
				if key == _current:
					_retro_mit(key, sh, s2, COVER_STEPS)
			)
	)


func _retro_mit(key: String, sh: Texture2D, licht: Texture2D, steps: int) -> void:
	_retro_key = key
	_show(licht, key, -soft_radius(steps), RETRO_LICHT)
	if is_instance_valid(_retro):
		_retro.zeigen([sh], retro_box(size if size.x > 0 else Vector2(1920, 1080), stage_rect()))


## Fläche des Bildschirms auf der Startseite (Uzai-Punkte): im Spielbild oben rechts (stage_rect),
## rechts bündig mit dem Seitenrand (96), unter der Kopfleiste und über den Quellen – höchstens 4 : 3.
const RETRO_RAND := 96.0
const RETRO_OBEN := 124.0


static func retro_box(view: Vector2, stage: Rect2) -> Rect2:
	var st := Rect2(stage.position * view, stage.size * view)
	var rechts := minf(st.end.x, view.x) - RETRO_RAND
	var oben := maxf(st.position.y, 0.0) + RETRO_OBEN
	var unten := st.position.y + st.size.y * 0.7
	var h := maxf(unten - oben, 0.0)
	var w := minf(st.size.x * 0.42, roundf(h * 4.0 / 3.0))
	return Rect2(rechts - w, oben, w, h)


## Area of the large image on the game page (game_page.gd: full width, this tall). Defined here
## so the home screen can preload it for the selected game (same area, same crop from
## Media.fit_texture). As tall as the image itself (Steam and SteamGridDB deliver heroes at
## 1920 × 620 or 3840 × 1240): at 820 pixels height it was enlarged by a third and cropped at
## the sides, which made it look zoomed in and blurry.
const PAGE_HERO_SEITEN := 1920.0 / 620.0


static func page_hero_area(view: Vector2) -> Vector2:
	var w: float = roundf(view.x if view.x > 0 else 1920.0)
	return Vector2(w, roundf(w / PAGE_HERO_SEITEN))


## Fläche des Spielbilds oben rechts (Uzai-Punkte).
func stage_size() -> Vector2:
	var vs := size if size.x > 0 and size.y > 0 else Vector2(1920, 1080)
	return (vs * stage_rect().size * Vector2(1.0, BILD_H)).round()


## Größe, in der das Spielbild geladen wird: die Fläche, aber höchstens 1920 Bildpunkte breit.
## In 4K wären es sonst 2764 × 1468 (16 MB je Bild auf die Grafikkarte) – für ein Bild, das nach
## links und unten ausläuft, sieht man den Unterschied nicht, das Hochladen aber schon.
const FIT_MAX_PX := 1920.0


func fit_size() -> Vector2:
	var a := stage_size()
	var px := a.x * Media.px_scale()
	return (a * (FIT_MAX_PX / px)).round() if px > FIT_MAX_PX else a


## Nachbarn im Regal vorab laden (nur Bilder, die schon auf der Platte liegen), damit der
## Wechsel dorthin sofort geht: Dekodiert wird im Hintergrund-Thread, hochgeladen über die
## Warteschlange in Media – ein Bild der Fläche kostet den Hauptthread etwa 2 ms (1080p).
## Neue Wünsche ersetzen die alten; geladen wird eins nach dem anderen, kurz nach dem Wechsel
## (nicht im selben Bild wie Titel, Meta-Zeile und Überblendung).
var _pre_list: Array = []
var _pre_id := 0
## Dekodiert wird gleich (Hilfsthread); hochgeladen erst nach der Überblendung (Media hält
## nicht dringende Bilder während einer Überblendung zurück – sonst stockte sie).
const PREFETCH_AFTER := 0.06


func prefetch(games: Array, soft := false) -> void:
	if _mode != "game":
		return
	if soft:
		# Weiche Fassungen sind winzig: alle gleich anstoßen (Hilfsthread, im Cache von Media).
		for g in games:
			var hp := Media.local_path(g, "hero")
			if hp != "" and not Media.has_soft(hp, HOME_STEPS):
				Media.soft_file(hp, HOME_STEPS, func(_t: Texture2D) -> void: pass)
		return
	_pre_list = games.duplicate()
	_pre_id += 1
	var my := _pre_id
	await get_tree().create_timer(PREFETCH_AFTER).timeout
	if my == _pre_id:
		_prefetch_next(my)


func _prefetch_next(my: int) -> void:
	var area := fit_size()
	while my == _pre_id and not _pre_list.is_empty():
		var g: Dictionary = _pre_list.pop_front()
		var hp := Media.local_path(g, "hero")
		if hp == "" or Media.has_fit(hp, area):
			continue
		Media.fit_texture(hp, area, func(_t: Texture2D) -> void:
			if my == _pre_id:
				_prefetch_next(my)
		)
		return


## Raumfarbe aus dem Cover des Spiels (sonst aus der Farbe seines Systems).
func tint_game(game: Dictionary) -> void:
	if not tint_on():
		return
	var key := "g:" + str(game.get("id", ""))
	_tint_key = key
	var sys := Config.system(str(game.get("system", "")))
	if sys.has("color"):
		_set_ground(ground_from(Color(str(sys.color))))
		_set_aurora(Color(str(sys.color)))
	Media.game_tint(game, func(c: Variant) -> void:
		if _tint_key == key and c is Color:
			_set_ground(ground_from(c))
			_set_aurora(c)
	)


func show_texture(t: Texture2D, key: String, blur := 0.0) -> void:
	if _mode != "game":
		return
	_current = key
	_tint_texture(t, key)
	_show(t, key, blur)


## Bild zu Videos, Filmen und Musik (zum Beispiel das Vorschaubild eines Videos): an derselben
## Stelle wie ein Spielbild, sofort (das Bild ist schon geladen). Nur sehr kleine Bilder (selbst
## erzeugte Farbfelder, Platzhalter) werden im Shader weichgezeichnet.
func show_blurred(t: Texture2D, key: String) -> void:
	if _mode != "game" or key == _current:
		return
	_current = key
	_dwell_id += 1
	_tint_texture(t, key)
	var small := t != null and t.get_width() < 200
	_show(t, key, -0.02 if small else 0.0, 0.9)


## Albumbild (Musik: läuft gerade, gewählte Kachel) weich an der Stelle des Spielbilds – genauso
## wie ein Cover ohne Hero (siehe _show_fallback): im Hintergrund-Thread aus der Datei auf etwa
## 2 × ART_STEPS Punkte klein gerechnet (Media.soft), der BLUR-Weg im Shader glättet nur noch.
## Früher kam das Albumbild (300–640 Punkte) über show_texture(…, 5.0) auf den Schirm: eine
## grobe Mipmap-Stufe (etwa 140 Punkte, zehnfach hochgezogen) und 12 weit gestreute Proben –
## feine Muster schienen als Klötzchen-Raster durch, wie anfangs bei den Spielen.
const ART_STEPS := COVER_STEPS
const ART_LEVEL := 0.85


func show_soft(t: Texture2D, key: String, level := ART_LEVEL) -> void:
	if _mode != "game" or key == _current:
		return
	_current = key
	_dwell_id += 1
	_tint_texture(t, key)
	if t == null:
		_show(null, key, 0.0)
		return
	Media.soft(t, ART_STEPS, func(s: Texture2D) -> void:
		if key == _current and s:
			_show(s, key, -soft_radius(ART_STEPS), level)
	)


## Raum ohne Spielfarbe (zum Beispiel in den Einstellungen).
func neutral() -> void:
	_tint_key = ""
	_set_ground(UzTheme.col("bg"))
	_set_aurora(UzTheme.col("bg"))


func clear_image() -> void:
	# Ein eigenes Bild (Einstellung) gilt überall; nur das Spielbild geht.
	if _mode == "bild":
		return
	_current = ""
	_show(null, "", 0.0)


func _tint_texture(t: Texture2D, key: String) -> void:
	if not tint_on() or t == null:
		return
	_tint_key = key
	var c: Variant = Media.color_of(t)
	if c is Color:
		_set_ground(ground_from(c))
		_set_aurora(c)


## Aus einer kräftigen Farbe wird ein sehr dunkler Raum mit einem Hauch der Farbe; die Farbe
## selbst kommt aus den Verläufen darüber.
static func ground_from(c: Color) -> Color:
	if UzTheme.light:
		return Color.from_hsv(c.h, clampf(c.s * 0.35, 0.06, 0.22), 0.9)
	if c.s < 0.12:
		return UzTheme.col("bg")
	# Der Grundwert macht den Raum kräftiger oder zurückhaltender (tint_k).
	var k := float(UzTheme.bg_param("tint_k"))
	if absf(k - 1.0) < 0.001:
		return Color.from_hsv(c.h, clampf(c.s * 0.5, 0.14, 0.4), 0.075)
	return Color.from_hsv(c.h, clampf(c.s * 0.5 * sqrt(k), 0.14 * minf(k, 1.0), minf(0.4 * sqrt(k), 0.75)), clampf(0.075 * k, 0.03, 0.2))


func _set_ground(c: Color, instant := false) -> void:
	if _ground_tw:
		_ground_tw.kill()
	if instant:
		_ground = c
		_room_mat.set_shader_parameter("ground", c)
		queue_redraw()
		return
	_ground_tw = create_tween()
	_ground_tw.tween_method(func(v: Color) -> void:
		_ground = v
		_room_mat.set_shader_parameter("ground", v)
		queue_redraw()
	, _ground, c, 0.3).set_trans(Tween.TRANS_SINE)


## Zur Stärke 0…6 (wie blur_params) die Feinheit des Weichzeichners: etwa so viele „Flecken“
## passen über die Bildbreite. Je kleiner, desto weicher.
static func soft_steps(level: float) -> int:
	var bp := blur_params(level)
	var sigma := bp.y / 2.1 + 0.5 * pow(2.0, bp.x) / 640.0
	return clampi(int(round(0.6 / maxf(sigma, 0.001))), 8, 400)


## Sauberer Weichzeichner in zwei Schritten: Media.soft/game_soft rechnen das Bild im
## Hintergrund-Thread auf etwa 2 × steps Punkte Breite klein (Media.soft_image), der Shader
## (BLUR, radius = soft_radius) streut dann 12 Proben über gut einen Bildpunkt davon; die Proben
## liegen dichter als die Punkte, das Ergebnis ist glatt. Früher kamen die 32 Proben aus einer
## großen Mipmap-Stufe und lagen mehrere Punkte auseinander – das gab Streifen und Blöcke, auf
## großen Fernsehern sah das pixelig aus.
static func soft_image(src: Image, steps: int) -> Image:
	return MediaS.soft_image(src, steps)


## Radius (in Bildbreiten) für den BLUR-Shader zu einem Bild aus Media.soft(t, steps, …).
static func soft_radius(steps: int) -> float:
	return 0.74 / float(maxi(steps, 1))


var _fade_tw: Tween


# --- Spielstart: das Bild tritt nach vorn ---------------------------------------------------------

## Steht das Bild gerade vorn (nach_vorn)? Dann ordnet zurueck() es wieder ein.
var vorn := false


## Spielstart (Plan „Gefühl“, Spielen holt das Bild nach vorn): Das Bild des Spiels, das hinter
## der Startseite liegt, füllt in T_RAUM den Schirm – ohne Verläufe und Abdunklung. Scharf wird es
## mit der Spielstart-Karte, die mit dem scharfen Bild darüber kommt (launch_card.gd aus_dem_bild);
## eine zweite, anders zugeschnittene Fassung hier läge nur doppelt im Bild. false, wenn es kein
## Bild gibt (dann bleibt alles, wie es ist).
func nach_vorn(_game: Dictionary) -> bool:
	if _mode != "game" or vorn:
		return false
	var front := _a if _a.modulate.a >= _b.modulate.a else _b
	var back := _b if front == _a else _a
	if front.texture == null or front.modulate.a < 0.05:
		return false
	vorn = true
	if _fade_tw:
		_fade_tw.kill()
	# Das Licht (weiches Cover) füllt den Schirm; der Bildschirm der Retro-Bühne tritt zurück.
	_retro_key = ""
	if is_instance_valid(_retro):
		_retro.weg()
	back.modulate.a = 0.0
	var tw := U.ankommen(self, U.T_RAUM, "uz_vorn").set_parallel(true)
	for side in ["anchor_left", "anchor_top"]:
		tw.tween_property(front, side, 0.0, U.T_RAUM)
	for side in ["anchor_right", "anchor_bottom"]:
		tw.tween_property(front, side, 1.0, U.T_RAUM)
	var m := front.material as ShaderMaterial
	for k in ["mask", "shade", "top_dim"]:
		tw.tween_method(func(v: float) -> void: m.set_shader_parameter(k, v), float(m.get_shader_parameter(k)), 0.0, U.T_RAUM)
	tw.tween_property(front, "modulate:a", 1.0, U.T_RAUM)
	return true


## Nach dem Spiel (oder wenn es nicht startet): das Bild wieder an seinen Platz, sofort – die
## Spielstart-Karte deckt dabei den Schirm.
func zurueck() -> void:
	if not vorn:
		return
	vorn = false
	U.stop(self, "uz_vorn")
	_arrange()
	_current = ""


func _show(t: Texture2D, key: String, blur: float, level := 1.0) -> void:
	# Die weniger sichtbare Ebene nimmt das neue Bild (bei schnellem Wechsel kein Bildsprung
	# auf einer noch halb sichtbaren Ebene); der laufende Übergang wird übernommen, nicht gestapelt.
	var nxt := _a if _a.modulate.a < _b.modulate.a else _b
	var old := _b if nxt == _a else _a
	if _fade_tw:
		_fade_tw.kill()
	# Ein anderes Bild: Der Bildschirm der Retro-Bühne geht mit seinem Licht.
	if key != _retro_key or t == null:
		_retro_key = ""
		if is_instance_valid(_retro):
			_retro.weg()
	# Die neue Ebene fängt unsichtbar an (bei schnellem Wechsel stand dort noch ein halb
	# eingeblendetes Bild – das neue wäre sonst mit einem Sprung erschienen).
	if _mode == "game" and t:
		nxt.modulate.a = 0.0
	# Vorschaubilder von Videos und Filmen: Ausschnitt dort, wo das Wichtige ist (Spielbilder kommen
	# schon passend zugeschnitten aus Media.fit_texture).
	Zuschnitt.put(nxt, t, false, false)
	# blur < 0: das Bild kommt aus Media.soft (schon klein gerechnet), -blur ist der Shader-Radius.
	var bp := Vector2(0.0, -blur) if blur < 0.0 else blur_params(blur)
	(nxt.material as ShaderMaterial).set_shader_parameter("lod", bp.x)
	(nxt.material as ShaderMaterial).set_shader_parameter("radius", bp.y)
	(nxt.material as ShaderMaterial).set_shader_parameter("taps", blur_taps())
	# Das Bild steht still. (Früher trieb es ganz langsam hin und her; so langsame Bewegung
	# springt in Bildpunkten und wirkt wie Ruckeln.)
	nxt.scale = Vector2.ONE
	# Statt zu treiben, setzt sich das neue Bild einmal: aus 3,5 % näher an seinen Platz (T_LICHT,
	# Kurve „Ankommen“, im Shader – gleitet ohne Pixelsprünge). Ruhig und leicht: steht gleich.
	var zm := nxt.material as ShaderMaterial
	if t and _mode == "game" and not U.reduziert() and not Leicht.active:
		zm.set_shader_parameter("zoom", 1.035)
		U.tw(nxt, "uz_hero_zoom", Tween.TRANS_QUART).tween_method(func(v: float) -> void: zm.set_shader_parameter("zoom", v), 1.035, 1.0, U.T_LICHT)
	else:
		U.stop(nxt, "uz_hero_zoom")
		zm.set_shader_parameter("zoom", 1.0)
	# Das neue Bild liegt über dem alten und blendet auf; das alte geht erst langsam, dann schnell
	# (kein dunkles Loch in der Mitte des Wechsels).
	if _mode == "game" and nxt.get_index() < old.get_index():
		move_child(nxt, old.get_index())
	Media.hold_uploads(FADE_S + 0.05)
	_fade_until = Time.get_ticks_msec() + int(FADE_S * 1000.0) + 60
	_fade_tw = create_tween().set_parallel(true)
	# Echte Überblendung: Das neue liegt oben und kommt gleichmäßig (sanft an und aus), das alte
	# bleibt darunter stehen und geht erst danach – kein Durchscheinen in der Mitte, kein
	# Nachziehen einer Seite, das wie ein Sprung wirkte. Steht das neue nur auf level (Startseite
	# 0,82), scheint das alte noch durch: Es geht dann sanft in T_WEG (sine in-out), nicht in einem
	# Bild – sonst sprang das Bild am Ende, wenn sonst alles stand. Ohne neues Bild geht das alte sanft.
	_fade_tw.tween_property(nxt, "modulate:a", (1.0 if _mode == "bild" else level) if t else 0.0, FADE_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if t and nxt.get_index() > old.get_index():
		_fade_tw.chain().tween_property(old, "modulate:a", 0.0, U.T_WEG).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		_fade_tw.tween_property(old, "modulate:a", 0.0, FADE_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


var _acc := 0.0
var _fade_until := 0
var _slow_logged := 0


func _process(dt: float) -> void:
	# Ruckler während einer Überblendung protokollieren (logs/leistung.log): Dauer des Bilds und die
	# letzten Uploads – so lässt sich am echten PC sehen, was die Überblendung aufhält.
	if dt > 0.05 and Time.get_ticks_msec() < _fade_until + 200 and _slow_logged < 200:
		_slow_logged += 1
		var ups: Array = Media.upload_log.filter(func(u): return Time.get_ticks_msec() - int(u[0]) < 400)
		Media.log_line("leistung", "Bildwechsel: Bild %d ms, Uploads %s" % [int(dt * 1000.0), str(ups.map(func(u): return "%s %d µs" % [u[1], int(u[2])]))])
	# Alles hier bewegt sich langsam: 30 Bilder pro Sekunde reichen völlig, nach 30 s ohne
	# Eingabe 12.
	if not is_visible_in_tree():
		return
	# Leichter Modus: Die Lichter stehen still; nur der Schwenk beim Bereichswechsel läuft.
	if Leicht.active:
		_acc = 0.0
		if _pan_tw and _pan_tw.is_running() and _aurora_on():
			_place_blobs()
		return
	_acc += dt
	var idle := Time.get_ticks_msec() - _last_input > 30000
	if _acc < (1.0 / 12.0 if idle else 1.0 / 30.0):
		return
	_aur_t += _acc
	_acc = 0.0
	if _aurora_on():
		_place_blobs()
	if _motes_on():
		queue_redraw()


## Im Spiel oder im Hintergrund: auch die Tweens anhalten (Bildtreiben, Farbwechsel). Sie
## laufen unabhängig von _process und hielten sonst jedes Bild „schmutzig“ – Uzai zeichnete dann
## weiter mit voller Bildrate samt Weichzeichner, obwohl es nicht zu sehen ist.
func pause_motion(on: bool) -> void:
	for t in [_aur_tw, _pan_tw, _ground_tw, _fade_tw]:
		if t is Tween and (t as Tween).is_valid():
			if on:
				(t as Tween).pause()
			else:
				(t as Tween).play()


func _input(e: InputEvent) -> void:
	if not (e is InputEventMouseMotion):
		_last_input = Time.get_ticks_msec()


func _motes_on() -> bool:
	var want: bool = Config.get_value("theme.motes", false)
	return _mode == "nebel" or (_mode == "game" and want and _a.modulate.a < 0.05 and _b.modulate.a < 0.05)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _ground)
	if _motes_on():
		# Leichter Modus: Die Punkte stehen still (an ihrem Platz, _process zeichnet nicht neu).
		var t := 0.0 if Leicht.active else Time.get_ticks_msec() / 1000.0
		var col := UzTheme.col("text")
		for m in _motes:
			var p: Vector2 = m.p
			p.y = fposmod(p.y - t * m.v * 0.25, 1.0)
			var pos := Vector2((p.x + sin(t * 0.2 + m.ph) * 0.01) * size.x, p.y * size.y)
			draw_circle(pos, m.r, Color(col, m.a * 0.5 * (0.55 + 0.45 * sin(t * 0.8 + m.ph))))

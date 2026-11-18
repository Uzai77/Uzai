extends Control
## Erfolgs-Pop-up: ein runder Knopf mit Pokal springt auf (0 → 115 % → 100 %), ein Lichtring
## läuft einmal aus, der Kreis öffnet sich zur gläsernen Pille, die Schrift gleitet herein
## („Erfolg freigeschaltet“, darunter der Name), rechts zählen die Uzai-Punkte hoch. Das Bild
## des Erfolgs blendet in den Kreis. Nach dem Halten schließt sich die Pille wieder zum Kreis,
## der kurz aufatmet und verschwindet. Seltene Erfolge: goldener Kreis und Schimmer, der zweimal
## über die Pille läuft; ultraselten: Platin; RetroAchievements: Bernstein, Pixel-Pokal,
## gestufter Schimmer mit Zeilen wie auf einem Röhrenbildschirm. „komplett“ (der letzte Erfolg
## eines Spiels, der große Moment): helles Gold, zwei Schimmer und für gut zwei Sekunden kleine
## Funken, die um den Kreis aufsteigen – kurz, dann Ruhe. Das Theme (Punkt 28) färbt die
## gewöhnliche Art (Glas, Licht, Kreis) und bestimmt die Form (Pille bis eckig); seltene
## behalten ihr Metall.
##
## Alles hängt an einer Zahl: t (Sekunden seit Beginn). frame(t, hold) rechnet daraus jede
## Größe (reine Funktion, siehe tests/logic_erfolge_popup.gd); ein einziger Tween treibt t.
## Pille, Kreis, Ring und Schimmer zeichnet ein Shader als Abstandsfeld (scharf bei jeder
## Auflösung, ohne Neuaufbau); Schrift, Pokal und Bild zeichnet _draw ohne Container und Layout.

signal finished

const AREA := Vector2(1280, 300)    ## Größe des Bereichs (1080p-Punkte), Pille in der Mitte
const H := 92.0                       ## Höhe der Pille = Durchmesser des Kreises
const R := 46.0
const DISC_INSET := 7.0
const MIN_W := 600.0
const MAX_W := 1060.0
const TEXT_GAP := 18.0                ## Kreis → Schrift
const PTS_GAP := 44.0                 ## Schrift → Punkte
const PAD_R := 34.0
const IN_END := 1.0                   ## ab hier steht alles; dann hold Sekunden halten
## Achievement description, so it is clear what was unlocked: for DESC_AB seconds after IN_END the top line shows
## „Erfolg freigeschaltet“, then the line fades to the description over DESC_T. If the pill stays for less than
## DESC_MIN (more are waiting), the description shows from the start.
const DESC_AB := 1.0
const DESC_T := 0.3
const DESC_MIN := 2.0
const OUT_LEN := 0.8

const INK := Color("#f3f1ec")
const MUTED := Color("#a6a49f")
const FAINT := Color("#8a877f")

## Farben je Art: Glas oben/unten, Licht (Ring, Zeile 1), Kreis oben/unten, Pokal, Schimmer.
const PALETTES := {
	"normal": { "top": Color(0.149, 0.153, 0.173, 0.96), "bot": Color(0.082, 0.086, 0.098, 0.96), "light": Color("#e7c27d"),
		"disc_a": Color("#3b3c42"), "disc_b": Color("#232428"), "glyph": Color("#e7c27d"), "sweep": Color(1, 1, 1), "sweep_a": 0.085,
		"warm": 0.0, "edge": 0.0, "line1": Color("#c9c5bc"), "pts": INK, "sweeps": 1 },
	"rare": { "top": Color(0.17, 0.153, 0.125, 0.965), "bot": Color(0.09, 0.078, 0.059, 0.965), "light": Color("#ecc77f"),
		"disc_a": Color("#f8e2a6"), "disc_b": Color("#c3924a"), "glyph": Color("#3b2a10"), "sweep": Color("#ffe3a0"), "sweep_a": 0.42,
		"warm": 0.55, "edge": 0.9, "line1": Color("#ecc77f"), "pts": Color("#f3d48f"), "sweeps": 2 },
	"ultra": { "top": Color(0.15, 0.163, 0.184, 0.965), "bot": Color(0.075, 0.086, 0.102, 0.965), "light": Color("#e4edf7"),
		"disc_a": Color("#fbfcfe"), "disc_b": Color("#a9b5c3"), "glyph": Color("#1d2530"), "sweep": Color("#ffffff"), "sweep_a": 0.30,
		"warm": 0.35, "edge": 1.0, "line1": Color("#dfe8f3"), "pts": Color("#f4f8fc"), "sweeps": 2 },
	"retro": { "top": Color(0.157, 0.141, 0.122, 0.965), "bot": Color(0.082, 0.075, 0.063, 0.965), "light": Color("#ffb46a"),
		"disc_a": Color("#3d352b"), "disc_b": Color("#221e18"), "glyph": Color("#ffb46a"), "sweep": Color("#ffc890"), "sweep_a": 0.20,
		"warm": 0.25, "edge": 0.0, "line1": Color("#ffbf80"), "pts": INK, "sweeps": 1 },
	"komplett": { "top": Color(0.184, 0.163, 0.122, 0.97), "bot": Color(0.094, 0.082, 0.055, 0.97), "light": Color("#f3d48f"),
		"disc_a": Color("#fff1c2"), "disc_b": Color("#d4a24e"), "glyph": Color("#3b2a10"), "sweep": Color("#fff0c0"), "sweep_a": 0.5,
		"warm": 0.7, "edge": 1.0, "line1": Color("#f3d48f"), "pts": Color("#f8e3a6"), "sweeps": 2, "glints": 1 },
}

const GLINTS := 12                    ## Funken der Art „komplett“
const GLINT_FROM := 0.12              ## Funken: Beginn und Ende (Sekunden seit Beginn)
const GLINT_TO := 2.4

const SHADER := """
shader_type canvas_item;
render_mode blend_premul_alpha;

uniform vec2 area = vec2(1280.0, 300.0);
uniform vec2 pc;                 // Mitte der Pille
uniform vec2 ph;                 // halbe Größe der Pille
uniform float k_alpha = 1.0;
uniform vec4 fill_top : source_color;
uniform vec4 fill_bot : source_color;
uniform vec4 light : source_color;
uniform vec2 dc;                 // Mitte des Kreises
uniform float dr;                // Halbmesser des Kreises
uniform vec4 disc_a : source_color;
uniform vec4 disc_b : source_color;
uniform float ring = -1.0;       // Lichtring 0..1, < 0 aus
uniform float sweep = -1.0;      // Schimmer 0..1 über die Pille, < 0 aus
uniform float sweep_a = 0.0;
uniform vec4 sweep_col : source_color;
uniform float warm = 0.0;
uniform float edge = 0.0;
uniform float retro = 0.0;
uniform float corner = 1.0;      // Form aus dem Theme: 1 = Pille, 0 = fast eckig

float rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float cov(float d) {
	float w = max(fwidth(d), 0.0001);
	return clamp(0.5 - d / w, 0.0, 1.0);
}

vec4 over(vec4 top, vec4 under) {
	return top + under * (1.0 - top.a);
}

void fragment() {
	vec2 p = UV * area;
	// Geschlossen immer ein Kreis; offen mit der Rundung des Themes.
	float r = mix(mix(8.0, ph.y, corner), ph.y, clamp(1.0 - (ph.x - ph.y) / max(ph.y, 1.0), 0.0, 1.0));
	vec4 acc = vec4(0.0);
	if (ph.x > 0.5 && k_alpha > 0.001) {
		// Schatten (Höhenstufe 3: weich, dunkel, nach unten)
		float ds = rbox(p - pc - vec2(0.0, 16.0), ph, r);
		float sh = (1.0 - smoothstep(-26.0, 44.0, ds)) * 0.5;
		acc = vec4(0.0, 0.0, 0.0, sh);
		// Glas
		float d = rbox(p - pc, ph, r);
		float c = cov(d);
		float gy = clamp((p.y - (pc.y - r)) / (2.0 * r), 0.0, 1.0);
		vec3 body = mix(fill_top.rgb, fill_bot.rgb, smoothstep(0.0, 1.0, gy));
		body = mix(body, light.rgb, warm * (0.07 + 0.06 * (1.0 - gy)));
		// Licht von oben an der Innenkante (Glas), unten kaum
		body += vec3(0.055) * smoothstep(-10.0, -0.5, d) * pow(1.0 - gy, 2.0);
		float sw = 0.0;
		float wide = 0.0;
		if (sweep >= 0.0) {
			float u = (p.x - (pc.x - ph.x)) / max(2.0 * ph.x, 1.0);
			float diag = u + (p.y - pc.y) / max(2.0 * ph.x, 1.0) * 0.9;
			float x = diag - (sweep * 1.5 - 0.25);
			if (retro > 0.5) {
				x = (floor(x * 22.0) + 0.5) / 22.0;
			}
			float band = exp(-x * x / (2.0 * 0.028 * 0.028));
			wide = exp(-x * x / (2.0 * 0.11 * 0.11));
			sw = (band * 0.8 + wide * 0.35) * sweep_a;
			if (retro > 0.5) {
				sw *= 0.55 + 0.45 * step(0.5, fract(p.y / 4.0));
			}
			body += sweep_col.rgb * sw;
		}
		// Kante glänzt, wo der Schimmer vorbeiläuft (nur seltene Erfolge)
		float rim = smoothstep(-2.6, -0.4, d) * (1.0 - smoothstep(-0.4, 0.6, d));
		body += light.rgb * rim * edge * (0.12 + 0.9 * wide * step(0.0, sweep));
		float ba = fill_top.a * c;
		acc = over(vec4(body * ba, ba), acc);
		// Kreis
		float dd = length(p - dc) - dr;
		float dcv = cov(dd);
		float gd = clamp((p.y - (dc.y - dr)) / max(2.0 * dr, 1.0), 0.0, 1.0);
		vec3 dcol = mix(disc_a.rgb, disc_b.rgb, smoothstep(0.0, 1.0, gd));
		dcol += vec3(0.07) * smoothstep(-4.0, -0.5, dd) * pow(1.0 - gd, 1.5);
		dcol += sweep_col.rgb * sw * 0.8;
		float da = disc_a.a * dcv;
		acc = over(vec4(dcol * da, da), acc);
		// Lichtring, läuft einmal nach außen aus
		if (ring >= 0.0 && ring < 1.0) {
			float rr = mix(dr + 2.0, r * 2.25, ring);
			float dist = abs(length(p - dc) - rr);
			float th = mix(2.6, 0.8, ring);
			float fade = pow(1.0 - ring, 1.7);
			float g = (cov(dist - th) * 0.75 + exp(-dist * dist / (2.0 * 9.0 * 9.0)) * 0.45) * fade * 0.7;
			acc += vec4(light.rgb * g, g);
		}
	}
	acc = clamp(acc, 0.0, 1.0) * k_alpha;
	COLOR = acc;
}
"""

static var _shader: Shader
static var _glyphs := {}

var entry: Dictionary = {}
var deco: Dictionary = {}
var hold := 3.4
var total := 0.0
var t := 0.0: set = _set_t
var playing := false

var _rect: ColorRect
var _mat: ShaderMaterial
var _ink: Control
var _pal: Dictionary
var _w_full := MIN_W
var _l1 := ""
var _l2 := ""
var _l1b := ""                    ## die Beschreibung des Erfolgs: löst Zeile 1 nach DESC_AB Sekunden ab
var _chip := ""
var _points := 0
var _icon: Texture2D
var _f1: Font
var _f2: Font
var _fp: Font
var _fc: Font
const S1 := 19
const S2 := 27
const SP := 36
const SC := 15
var _tw: Tween
var _f: Dictionary = {}


## entry: { name, icon, points, … } (Unlocks), deco: Unlocks.decorate(entry).
func setup(e: Dictionary, d: Dictionary, hold_sec := 3.4) -> Control:
	entry = e
	deco = d
	hold = hold_sec
	total = IN_END + hold + OUT_LEN
	_pal = PALETTES.get(str(d.get("variant", "normal")), PALETTES.normal)
	if _pal == PALETTES.normal:
		# Gewöhnliche Erfolge in den Farben des Themes (Graphit: genau die Werte oben).
		var tp: Dictionary = UzTheme.popup_palette()
		_pal = _pal.duplicate()
		_pal.top = tp.top
		_pal.bot = tp.bottom
		_pal.light = tp.light
		_pal.glyph = tp.light
		_pal.line1 = tp.line1
		_pal.disc_a = tp.disc_a
		_pal.disc_b = tp.disc_b
	custom_minimum_size = AREA
	size = AREA
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_f1 = UzTheme.font("medium")
	_f2 = UzTheme.ui("ui_bold")
	_fp = UzTheme.ui("ui_bold")
	_fc = UzTheme.font("medium")
	_points = int(e.get("points", 0))
	_chip = str(d.get("chip", ""))
	_measure()
	if not _shader:
		_shader = Shader.new()
		_shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.position = Vector2.ZERO
	_rect.size = AREA
	add_child(_rect)
	_ink = Control.new()
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink.size = AREA
	_ink.draw.connect(_draw_ink)
	add_child(_ink)
	_static_uniforms()
	var icon := str(e.get("icon", ""))
	if icon != "":
		var cb := func(tex: Texture2D) -> void:
			if is_instance_valid(self) and tex:
				_icon = tex
		if icon.begins_with("http"):
			Media.url_texture(icon, 128, cb)
		else:
			Media.file_texture(icon, 128, cb)
	_set_t(0.0)
	return self


## Abspielen (ein Tween auf t, linear: die Kurven stecken in frame()).
func play() -> void:
	playing = true
	_restart_tween()


## Es warten mehr: kürzer halten (nie mitten im Ausblenden springen).
func shorten(new_hold: float) -> void:
	if new_hold >= hold:
		return
	hold = maxf(new_hold, maxf(0.0, t - IN_END))
	total = IN_END + hold + OUT_LEN
	if playing:
		_restart_tween()


func _restart_tween() -> void:
	if _tw and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(self, "t", total, maxf(total - t, 0.01)).from(t)
	_tw.tween_callback(func() -> void:
		playing = false
		finished.emit()
	)


func _set_t(v: float) -> void:
	t = v
	if _mat == null:
		return
	_f = frame(t, hold, int(_pal.get("sweeps", 1)), int(_pal.get("glints", 0)) > 0)
	_apply()


# --- Zeitplan (rein) ------------------------------------------------------------------------

static func seg(x: float, a: float, b: float) -> float:
	return clampf((x - a) / (b - a), 0.0, 1.0)


static func out_cubic(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func out_quint(x: float) -> float:
	return 1.0 - pow(1.0 - x, 5.0)


static func out_expo(x: float) -> float:
	return 1.0 if x >= 1.0 else 1.0 - pow(2.0, -10.0 * x)


static func in_out_cubic(x: float) -> float:
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0


static func in_out_sine(x: float) -> float:
	return -(cos(PI * x) - 1.0) / 2.0


## Alle Größen zur Zeit t: s (Größe des Kreises), a (Deckkraft), wk (Breite 0 = Kreis, 1 = Pille),
## l1a/l1x, l2a/l2x (Zeilen: Deckkraft, Versatz), pa (Punkte sichtbar), pk (Zählstand 0..1),
## pb (Punkte-Puls), ik (Bild im Kreis 0..1), ring (Lichtring 0..1 oder -1), sweep (-1 oder 0..1),
## glint (Funken 0..1 oder -1, nur mit glints), done.
static func frame(t: float, hold: float, sweeps := 1, glints := false) -> Dictionary:
	var he := IN_END + hold                  # Ende des Haltens
	var f := {}
	# Aufspringen: 0 → 1,15 (0,22 s), zurück auf 1 (0,16 s); am Ende kurz 1,06, dann weg.
	var s := 0.0
	if t < 0.22:
		s = 1.15 * out_cubic(seg(t, 0.0, 0.22))
	elif t < 0.38:
		s = lerpf(1.15, 1.0, in_out_sine(seg(t, 0.22, 0.38)))
	else:
		s = 1.0
	var o0 := he + 0.52
	if t >= o0:
		# kurz aufatmen, dann zügig zusammenfallen (beschleunigend, ohne Zurückziehen)
		if t < o0 + 0.09:
			s = lerpf(1.0, 1.08, out_cubic(seg(t, o0, o0 + 0.09)))
		else:
			var k := seg(t, o0 + 0.09, o0 + 0.28)
			s = 1.08 * (1.0 - k * k)
	f.s = maxf(s, 0.0)
	f.a = minf(1.0, t / 0.06) * (1.0 - seg(t, o0 + 0.17, o0 + 0.28))
	# Öffnen zur Pille, später wieder schließen.
	var wk := out_quint(seg(t, 0.30, 0.88))
	wk *= 1.0 - in_out_cubic(seg(t, he + 0.12, he + 0.52))
	f.wk = wk
	# Schrift: Zeile 1, dann Zeile 2, je mit leichtem Gleiten von links.
	var out_k := seg(t, he, he + 0.2)
	f.l1a = out_cubic(seg(t, 0.52, 0.86)) * (1.0 - out_k)
	f.l1x = -16.0 * (1.0 - out_expo(seg(t, 0.52, 0.98))) - 10.0 * out_k * out_k
	f.l2a = out_cubic(seg(t, 0.60, 0.94)) * (1.0 - out_k)
	f.l2x = -16.0 * (1.0 - out_expo(seg(t, 0.60, 1.06))) - 10.0 * out_k * out_k
	f.pa = out_cubic(seg(t, 0.62, 0.90)) * (1.0 - out_k)
	f.pk = out_cubic(seg(t, 0.70, 1.30))
	f.pb = 1.0 + 0.16 * sin(PI * seg(t, 1.30, 1.50))
	f.ik = out_cubic(seg(t, 1.05, 1.45))
	f.ring = seg(t, 0.08, 0.83) if t >= 0.08 and t < 0.83 else -1.0
	# Schimmer: einmal (normal), seltene zweimal – der zweite nur, wenn genug Zeit ist.
	var sw := -1.0
	if t >= 1.0 and t < 1.8:
		sw = seg(t, 1.0, 1.8)
	elif sweeps > 1 and he - 0.25 >= 3.1 and t >= 2.3 and t < 3.1:
		sw = seg(t, 2.3, 3.1)
	f.sweep = sw
	# Funken (komplett): gleich nach dem Aufspringen, höchstens bis GLINT_TO, nie ins Ausblenden.
	f.glint = seg(t, GLINT_FROM, GLINT_TO) if glints and t >= GLINT_FROM and t < minf(GLINT_TO, he) else -1.0
	f.done = t >= he + OUT_LEN
	return f


# --- Maße -----------------------------------------------------------------------------------

func _measure() -> void:
	var l1 := str(deco.get("line1", "Erfolg freigeschaltet"))
	var l2 := str(entry.get("name", ""))
	var pw := maxf(_fp.get_string_size(tr("+100"), HORIZONTAL_ALIGNMENT_LEFT, -1, SP).x,
			_fc.get_string_size(tr("Uzai-Punkte"), HORIZONTAL_ALIGNMENT_LEFT, -1, SC).x)
	var chip_w := _chip_w()
	# Zeile 2 ist der Name des Erfolgs (von Steam bzw. RetroAchievements): nie übersetzen.
	var tw := maxf(_f1.get_string_size(tr(l1), HORIZONTAL_ALIGNMENT_LEFT, -1, S1).x + chip_w, _f2.get_string_size(l2, HORIZONTAL_ALIGNMENT_LEFT, -1, S2).x)
	# Die Beschreibung (fremder Text wie der Name: nie übersetzen) darf die Pille bis MAX_W verbreitern.
	var desc := str(entry.get("desc", "")).strip_edges().replace("\n", " ")
	if desc == l2:
		desc = ""
	if desc != "":
		tw = maxf(tw, _f1.get_string_size(desc, HORIZONTAL_ALIGNMENT_LEFT, -1, S1).x)
	var fixed := H + TEXT_GAP + PTS_GAP + pw + PAD_R
	_w_full = clampf(fixed + tw, MIN_W, MAX_W)
	var room := _w_full - fixed
	_l1 = fit(_f1, l1, S1, room - chip_w)
	_l2 = fit(_f2, l2, S2, room, false)
	_l1b = fit(_f1, desc, S1, room, false) if desc != "" else ""


## Wie weit die Beschreibung Zeile 1 abgelöst hat (0 … 1) zum Zeitpunkt zeit bei der Haltezeit halten.
static func desc_k(zeit: float, halten: float, hat_desc: bool) -> float:
	if not hat_desc:
		return 0.0
	if halten < DESC_MIN:
		return 1.0
	return seg(zeit, IN_END + DESC_AB, IN_END + DESC_AB + DESC_T)


func _chip_w() -> float:
	return 0.0 if _chip == "" else _fc.get_string_size(tr(_chip), HORIZONTAL_ALIGNMENT_LEFT, -1, SC).x + 22.0 + 10.0


## Text auf Breite kürzen (mit …), ganze Wörter bevorzugt. uebersetzen = false: fremder Text (Name
## eines Erfolgs), gemessen wie er dasteht.
static func fit(font: Font, text: String, fs: int, w: float, uebersetzen := true) -> String:
	var voll := str(TranslationServer.translate(text)) if uebersetzen else text
	if font.get_string_size(voll, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w:
		return text
	var s := text
	while s.length() > 1 and font.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
		s = s.left(s.length() - 1)
	var sp := s.rfind(" ")
	if sp > s.length() * 0.6:
		s = s.left(sp)
	return s.strip_edges().trim_suffix(",").trim_suffix(" ·") + "…"


func full_width() -> float:
	return _w_full


func line1() -> String:
	return _l1


func line2() -> String:
	return _l2


# --- Zeichnen -------------------------------------------------------------------------------

func _static_uniforms() -> void:
	_mat.set_shader_parameter("area", AREA)
	_mat.set_shader_parameter("fill_top", _pal.top)
	_mat.set_shader_parameter("fill_bot", _pal.bot)
	_mat.set_shader_parameter("light", _pal.light)
	_mat.set_shader_parameter("disc_a", _pal.disc_a)
	_mat.set_shader_parameter("disc_b", _pal.disc_b)
	_mat.set_shader_parameter("sweep_col", _pal.sweep)
	_mat.set_shader_parameter("sweep_a", float(_pal.sweep_a))
	_mat.set_shader_parameter("warm", float(_pal.warm))
	_mat.set_shader_parameter("edge", float(_pal.edge))
	_mat.set_shader_parameter("retro", 1.0 if str(deco.get("variant", "")) == "retro" else 0.0)
	_mat.set_shader_parameter("corner", float(UzTheme.popup_palette().get("corner", 1.0)))


## Wo die Pille gerade steht: { c (Mitte), w (Breite), s, bc (Kreismitte), dr }.
func geometry() -> Dictionary:
	var c := AREA * 0.5
	var s: float = _f.get("s", 0.0)
	var w := lerpf(H, _w_full, float(_f.get("wk", 0.0)))
	var left := c.x - w * 0.5 * s
	var bc := Vector2(left + R * s, c.y)
	return { "c": c, "w": w, "s": s, "bc": bc, "dr": (R - DISC_INSET) * s, "left": left, "right": c.x + w * 0.5 * s }


func _apply() -> void:
	var g := geometry()
	_mat.set_shader_parameter("pc", g.c)
	_mat.set_shader_parameter("ph", Vector2(g.w * 0.5, R) * float(g.s))
	_mat.set_shader_parameter("dc", g.bc)
	_mat.set_shader_parameter("dr", g.dr)
	_mat.set_shader_parameter("k_alpha", float(_f.a))
	_mat.set_shader_parameter("ring", float(_f.ring))
	_mat.set_shader_parameter("sweep", float(_f.sweep))
	if is_instance_valid(_ink):
		_ink.queue_redraw()


func _draw_ink() -> void:
	var g := geometry()
	var a: float = _f.get("a", 0.0)
	var s: float = g.s
	if a <= 0.001 or s <= 0.001:
		return
	var bc: Vector2 = g.bc
	var dr: float = g.dr
	var ik: float = _f.ik if _icon else 0.0
	var retro := str(deco.get("variant", "")) == "retro"
	# Pokal im Kreis (weicht dem Bild des Erfolgs: wird kleiner und blasser)
	if ik < 1.0:
		var gs := 44.0 * s * (1.0 - 0.3 * ik)
		var gc: Color = _pal.glyph
		gc.a *= a * (1.0 - ik)
		if retro:
			_pixel_trophy(bc, gs, gc)
		else:
			var px := maxi(16, int(ceil(gs * _render_scale())))
			var tex := trophy_texture(px)
			_ink.draw_texture_rect(tex, Rect2(bc - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), false, gc)
	# Bild des Erfolgs (rund; Retro: kleines abgerundetes Quadrat wie die RA-Abzeichen)
	if ik > 0.0:
		var k := 0.86 + 0.14 * out_cubic(ik)
		var col := Color(1, 1, 1, a * ik)
		if retro:
			var half := (dr - 2.0) * 0.80 * k
			_ink.draw_colored_polygon(_round_rect_poly(bc, half, 9.0 * s), col, _round_rect_uv(bc, half, 9.0 * s), _icon)
		else:
			var rr := (dr - 2.5) * k
			var pts := _circle(bc, rr, 72)
			_ink.draw_colored_polygon(pts, col, _circle_uv(72), _icon)
			# weicher Rand gegen Treppen am Bildrand
			var edge_c: Color = _pal.disc_b
			edge_c.a = a * ik
			_ink.draw_arc(bc, rr, 0.0, TAU, 72, edge_c, 1.6, true)
	if float(_f.get("glint", -1.0)) >= 0.0:
		_glints(bc, dr, float(_f.glint), a)
	# Schrift und Punkte (nur in der offenen Pille)
	var x0: float = g.left + H + TEXT_GAP
	var cy: float = g.c.y
	var asc1 := _f1.get_ascent(S1)
	var asc2 := _f2.get_ascent(S2)
	var block := _f1.get_height(S1) + 2.0 + _f2.get_height(S2)
	var top := cy - block * 0.5 + 1.0
	var y1 := top + asc1
	var y2 := top + _f1.get_height(S1) + 2.0 + asc2
	var dk := desc_k(t, hold, _l1b != "")
	if _f.l1a > 0.001 and dk > 0.001:
		var cb: Color = _pal.line1
		cb.a *= _f.l1a * a * dk
		_ink.draw_string(_f1, Vector2(x0 + _f.l1x, y1), _l1b, HORIZONTAL_ALIGNMENT_LEFT, -1, S1, cb)
	if _f.l1a > 0.001 and dk < 0.999:
		var c1: Color = _pal.line1
		c1.a *= _f.l1a * a * (1.0 - dk)
		_ink.draw_string(_f1, Vector2(x0 + _f.l1x, y1), tr(_l1), HORIZONTAL_ALIGNMENT_LEFT, -1, S1, c1)
		if _chip != "":
			var cx: float = x0 + float(_f.l1x) + _f1.get_string_size(tr(_l1), HORIZONTAL_ALIGNMENT_LEFT, -1, S1).x + 10.0
			var cw := _fc.get_string_size(tr(_chip), HORIZONTAL_ALIGNMENT_LEFT, -1, SC).x + 22.0
			var ch := 24.0
			var cr := Rect2(cx, roundf(y1 - asc1 * 0.36 - ch * 0.5), cw, ch)
			var bg: Color = _pal.light
			bg.a = 0.2 * _f.l1a * a * (1.0 - dk)
			_ink.draw_style_box(_chip_box(bg), cr)
			var tc: Color = _pal.line1
			tc.a *= _f.l1a * a * (1.0 - dk)
			_ink.draw_string(_fc, Vector2(cr.position.x + 11.0, cr.position.y + (ch + _fc.get_ascent(SC) - _fc.get_descent(SC)) * 0.5), tr(_chip),
					HORIZONTAL_ALIGNMENT_LEFT, -1, SC, tc)
	if _f.l2a > 0.001:
		var c2 := INK
		c2.a *= _f.l2a * a
		_ink.draw_string(_f2, Vector2(x0 + _f.l2x, y2), _l2, HORIZONTAL_ALIGNMENT_LEFT, -1, S2, c2)
	if _f.pa > 0.001:
		var right: float = g.right - PAD_R
		var shown := roundi(float(_points) * float(_f.pk))
		var txt := "+%d" % shown
		var tw := _fp.get_string_size(tr(txt), HORIZONTAL_ALIGNMENT_LEFT, -1, SP).x
		var cpt: Color = _pal.pts
		cpt.a *= _f.pa * a
		var base := Vector2(right - tw, cy + 4.0)
		var pb: float = _f.pb
		if pb != 1.0:
			var pivot := Vector2(right - tw * 0.5, cy - 8.0)
			_ink.draw_set_transform(pivot * (1.0 - pb), 0.0, Vector2(pb, pb))
		_ink.draw_string(_fp, base, tr(txt), HORIZONTAL_ALIGNMENT_LEFT, -1, SP, cpt)
		_ink.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var cap := "Uzai-Punkte"
		var cw2 := _fc.get_string_size(tr(cap), HORIZONTAL_ALIGNMENT_LEFT, -1, SC).x
		var cc := FAINT
		cc.a *= _f.pa * a
		_ink.draw_string(_fc, Vector2(right - cw2, cy + 27.0), tr(cap), HORIZONTAL_ALIGNMENT_LEFT, -1, SC, cc)


## Kleine Funken um den Kreis (komplett): jeder steigt einmal ein Stück nach außen und oben,
## wird dabei hell und vergeht – gestaffelt, so dass immer nur ein paar zu sehen sind. Sie
## fliegen nach links, oben und unten aus der Pille, nie über die Schrift rechts vom Kreis.
## k: Fortschritt 0..1 über die ganze Funkenzeit.
func _glints(bc: Vector2, dr: float, k: float, a: float) -> void:
	var col: Color = _pal.light
	for i in GLINTS:
		var phase := fposmod(float(i) * 0.618 + 0.11, 1.0) * 0.6
		var u := clampf((k - phase) / 0.4, 0.0, 1.0)
		if u <= 0.0 or u >= 1.0:
			continue
		var w := sin(u * PI)
		# Winkel von 70° (oben rechts) über links bis 290° (unten rechts): der Bogen ohne die Schrift.
		var ang := PI * 0.39 + PI * 1.22 * (fposmod(float(i) * 0.37 + 0.05, 1.0))
		var rad := dr * 1.15 + 8.0 + u * 22.0
		var p := bc + Vector2(cos(ang), sin(ang)) * rad + Vector2(0.0, -u * 14.0)
		var sz := (2.5 + 3.5 * w) * maxf(0.6, float(_f.get("s", 1.0)))
		var c := Color(col, a * w * 0.9)
		_ink.draw_line(p - Vector2(sz, 0), p + Vector2(sz, 0), c, 1.6, true)
		_ink.draw_line(p - Vector2(0, sz), p + Vector2(0, sz), c, 1.6, true)
		_ink.draw_circle(p, 1.4 + w, Color(col, a * w))


func _render_scale() -> float:
	var vp := get_viewport()
	if vp == null:
		return 1.0
	return maxf(1.0, vp.get_final_transform().get_scale().x * get_global_transform_with_canvas().get_scale().x)


static func _chip_box(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(12)
	sb.anti_aliasing = true
	return sb


static func _circle(c: Vector2, r: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var ang := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	return pts


static func _circle_uv(n: int) -> PackedVector2Array:
	var uv := PackedVector2Array()
	for i in n:
		var ang := TAU * float(i) / float(n)
		uv.append(Vector2(0.5, 0.5) + Vector2(cos(ang), sin(ang)) * 0.5)
	return uv


static func _round_rect_poly(c: Vector2, half: float, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	r = minf(r, half)
	var corners := [Vector2(half - r, -half + r), Vector2(half - r, half - r), Vector2(-half + r, half - r), Vector2(-half + r, -half + r)]
	var start := [-PI / 2.0, 0.0, PI / 2.0, PI]
	for i in 4:
		for j in 7:
			var ang: float = start[i] + (PI / 2.0) * float(j) / 6.0
			pts.append(c + corners[i] + Vector2(cos(ang), sin(ang)) * r)
	return pts


static func _round_rect_uv(c: Vector2, half: float, r: float) -> PackedVector2Array:
	var uv := PackedVector2Array()
	for p in _round_rect_poly(c, half, r):
		uv.append((p - c) / (2.0 * half) + Vector2(0.5, 0.5))
	return uv


## Eigener, gefüllter Pokal (Schale, Henkel, Fuß) als Bild in genau dieser Größe.
static func trophy_texture(px: int) -> Texture2D:
	if _glyphs.has(px):
		return _glyphs[px]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">' \
		+ '<path fill="#fff" d="M6.2 3.2h11.6v5.4a5.8 5.8 0 0 1-11.6 0z"/>' \
		+ '<path fill="none" stroke="#fff" stroke-width="1.7" stroke-linecap="round" d="M6.3 5.1H4.2a.9.9 0 0 0-.9 1c.2 2.3 1.5 3.9 3.6 4.4M17.7 5.1h2.1a.9.9 0 0 1 .9 1c-.2 2.3-1.5 3.9-3.6 4.4"/>' \
		+ '<path fill="#fff" d="M10.6 14.1h2.8v3.3h-2.8z"/>' \
		+ '<path fill="#fff" d="M8.2 18.3h7.6a1.3 1.3 0 0 1 1.3 1.3v1.2H6.9v-1.2a1.3 1.3 0 0 1 1.3-1.3z"/>' \
		+ '</svg>'
	var img := Image.new()
	if img.load_svg_from_string(svg, float(px) / 24.0) != OK:
		img = Image.create(px, px, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	_glyphs[px] = tex
	return tex


const PIXEL_TROPHY := [
	"..XXXXXXXX..",
	"XXXXXXXXXXXX",
	"X.XXXXXXXX.X",
	"X.XXXXXXXX.X",
	".XXXXXXXXXX.",
	"..XXXXXXXX..",
	"...XXXXXX...",
	".....XX.....",
	".....XX.....",
	"....XXXX....",
	"...XXXXXX...",
	"...XXXXXX...",
]


## Retro: Pokal aus 12 × 12 Pixeln.
func _pixel_trophy(c: Vector2, sz: float, col: Color) -> void:
	var p := sz / 12.0
	var o := c - Vector2(sz, sz) * 0.5
	for y in PIXEL_TROPHY.size():
		var row: String = PIXEL_TROPHY[y]
		var x := 0
		while x < row.length():
			if row[x] == "X":
				var x2 := x
				while x2 < row.length() and row[x2] == "X":
					x2 += 1
				_ink.draw_rect(Rect2(o.x + x * p, o.y + y * p, (x2 - x) * p, p), col)
				x = x2
			else:
				x += 1

extends Control
## Spielstart-Karte (wie bei Switch und PS5): Sobald „Spielen“ gedrückt ist, füllt das Bild des
## Spiels den Schirm, in der Mitte sein Logo mit weichem Hof, unten eine feine Leiste, die ruhig
## schimmert, und in kleiner Schrift, was gerade passiert („Wird gestartet …“, System, „Steam
## überprüft Dateien …“). Das Bild driftet sehr langsam (Ken Burns, nur ein Wert im Shader, kein
## Neu-Anordnen). Ist das Spielfenster vorn, blendet die Karte in 0,3 s auf Schwarz (hand_over),
## dann gibt Uzai ab. Beim Zurückkommen zeigt sie kurz „Zurück in Uzai“ (returning).
##
## Schärfe: Bilder werden in Bildschirmpunkten geladen (4K: doppelt), nie über ihre eigene
## Größe gezogen (siehe launch_art.gd). Logo und Hülle liegen Punkt auf Punkt, das große Bild
## linear gefiltert; nur der weiche Grund nutzt Mipmaps. Gleiche Schnittstelle wie in_game.gd
## (set_status, set_running), main.gd nimmt die Karte, wenn „Spielstart-Karte“ an ist.

const U := preload("res://src/ui/u.gd")
const Arbeit := preload("res://src/core/arbeit.gd")
const Art := preload("res://src/ui/layers/launch_art.gd")
const SteamScanner := preload("res://src/library/steam_scanner.gd")
const VDF := preload("res://src/library/vdf.gd")

## Ken Burns: Zoom bis Art.KB_ZOOM und leichte Drift, weich auslaufend über etwa KB_TAU Sekunden.
const KB_TAU := 14.0
const KB_PAN := Vector2(-18.0, -6.0)
const T_ART := 0.36
const T_LOGO := 0.5
const T_OUT := 0.3
const STEAM_POLL := 1.5

const BACK_SHADER := """shader_type canvas_item;
uniform sampler2D art : filter_linear, repeat_disable;
uniform sampler2D art_mip : filter_linear_mipmap, repeat_disable;
uniform int mode = 0;
uniform vec2 view = vec2(1920.0, 1080.0);
uniform vec4 band = vec4(0.0, 0.0, 1920.0, 1080.0);
uniform vec4 edges = vec4(0.0);
uniform float feather = 150.0;
uniform float texw = 1920.0;
uniform float blur_base = 0.0;
uniform float zoom = 1.0;
uniform vec2 pan = vec2(0.0);
uniform float t = 0.0;
uniform float art_a = 0.0;
uniform vec4 ground : source_color = vec4(0.05, 0.05, 0.06, 1.0);
uniform vec4 pal : source_color = vec4(0.9, 0.75, 0.5, 1.0);
varying vec4 tint;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void vertex() {
	tint = COLOR;
}
vec3 colors(vec2 uv) {
	float asp = view.x / view.y;
	vec2 a = (uv - vec2(0.5, 0.44)) * vec2(asp, 1.0);
	float g1 = exp(-dot(a, a) * 2.4);
	vec2 b = (uv - vec2(0.5 + 0.22 * sin(t * 0.13), 0.9 + 0.05 * cos(t * 0.11))) * vec2(asp, 1.0);
	float g2 = exp(-dot(b, b) * 3.2);
	return ground.rgb + pal.rgb * (0.22 * g1 + 0.1 * g2);
}
vec3 art_at(vec2 p) {
	vec2 uv = (p - band.xy) / band.zw;
	float dl = edges.x > 0.5 ? p.x - band.x : 1e5;
	float dt = edges.y > 0.5 ? p.y - band.y : 1e5;
	float dr = edges.z > 0.5 ? band.x + band.z - p.x : 1e5;
	float db = edges.w > 0.5 ? band.y + band.w - p.y : 1e5;
	float e = min(min(dl, dr), min(dt, db));
	float r = max(0.0, feather - e) * 0.5 + blur_base;
	vec2 cuv = clamp(uv, vec2(0.0), vec2(1.0));
	vec3 sharp = texture(art, cuv).rgb;
	if (r < 0.75) {
		return sharp;
	}
	float rt = r * texw / band.z;
	float lod = max(0.0, log2(rt / 2.5));
	vec2 ruv = vec2(r / band.z, r / band.w);
	vec3 acc = vec3(0.0);
	float ws = 0.0;
	for (int i = 0; i < 12; i++) {
		float f = (float(i) + 0.5) / 12.0;
		float ang = float(i) * 2.39996;
		vec2 o = vec2(cos(ang), sin(ang)) * sqrt(f) * ruv;
		float w = exp(-f * 2.2);
		acc += textureLod(art_mip, clamp(cuv + o, vec2(0.001), vec2(0.999)), lod).rgb * w;
		ws += w;
	}
	return mix(sharp, acc / ws, smoothstep(0.75, 8.0, r));
}
void fragment() {
	vec2 p = UV * view;
	vec2 c = view * vec2(0.5, 0.46);
	vec2 q = c + (p - c) / zoom - pan;
	vec3 base = colors(UV);
	vec3 col = base;
	if (mode == 1) {
		vec3 a = art_at(q);
		float l = dot(a, vec3(0.2126, 0.7152, 0.0722));
		a = mix(vec3(l), a, 0.9);
		a = a * 0.86 + ground.rgb * (1.0 - l) * 0.4;
		a = mix(a, a * (0.7 + 0.6 * pal.rgb), 0.1);
		col = mix(base, a, art_a);
	}
	float asp = view.x / view.y;
	vec2 v = (UV - vec2(0.5, 0.46)) * vec2(asp * 0.6, 1.0);
	float vig = smoothstep(0.3, 1.0, length(v));
	col = mix(col, ground.rgb * 0.3, vig * 0.75);
	float low = smoothstep(0.58, 1.0, UV.y);
	col = mix(col, ground.rgb * 0.25, low * 0.62);
	col += (hash(FRAGCOORD.xy) - 0.5) / 255.0;
	COLOR = vec4(col, 1.0) * tint;
}
"""

## Feine Leiste: ein heller Abschnitt wandert ruhig durch (frac < 0), sonst Fortschritt.
const LINE_SHADER := """shader_type canvas_item;
uniform vec4 base_col : source_color = vec4(1.0, 1.0, 1.0, 0.14);
uniform vec4 hi : source_color = vec4(0.9, 0.76, 0.49, 1.0);
uniform float frac = -1.0;
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
void fragment() {
	float x = UV.x;
	vec4 c = base_col;
	if (frac >= 0.0) {
		float on = 1.0 - smoothstep(frac - 0.004, frac + 0.004, x);
		c = mix(c, hi, on * 0.9);
	} else {
		float pos = -0.35 + fract(TIME * 0.42) * 1.7;
		float g = exp(-pow((x - pos) / 0.16, 2.0));
		c = mix(c, hi, g);
	}
	c.a *= smoothstep(0.0, 0.1, x) * smoothstep(1.0, 0.9, x);
	COLOR = c * tint;
}
"""

static var _back_shader: Shader
static var _line_shader: Shader

var game: Dictionary = {}
## Was die Karte gewählt hat (für Proben und Tests): mode, sizes, up, logo_native, logo_size …
var info: Dictionary = {}

var _view := Vector2(1920, 1080)
var _pxs := 1.0
var _back: ColorRect
var _mat: ShaderMaterial
var _mid: Control
var _front_shadow: Panel
var _front: TextureRect
var _glow: TextureRect
var _logo: TextureRect
var _title: Label
var _bottom: VBoxContainer
var _line: ColorRect
var _line_mat: ShaderMaterial
var _status: Label
var _plat: Label
var _hint: HBoxContainer
var _black: ColorRect
var _t := 0.0
var _running := false
var _leaving := false
var _launch_text := "Wird gestartet …"
var _note := ""
var _job: Dictionary = {}
var _res: Dictionary = {}
var _paths: Dictionary = {}
var _poll_at := 0.0
var _manifest := ""
var _pal := Color(0.9, 0.76, 0.49)
var _ground := Color(0.05, 0.05, 0.06)
var _art_a := 0.0
## Aus dem Bild (aus_dem_bild): Das Spielbild des Hintergrunds ist schon nach vorn gekommen; die
## eigene Fläche blendet erst darüber, wenn ihr Bild da ist.
var _aus_bild := false
var _back_wartet := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_view = get_viewport_rect().size
	_pxs = clampf(get_tree().root.get_final_transform().get_scale().x, 0.25, 4.0)
	# Ohne Bild: Farbe des Systems (Emulator) bzw. ein ruhiges, leicht kühles Licht.
	_pal = Color(0.55, 0.6, 0.72)
	var sys := Config.system(str(game.get("system", "")))
	if str(sys.get("color", "")) != "" and game.get("source") == "rom":
		_pal = Color(str(sys.color)).lightened(0.15)
	_ground = Art.ground_of(UzTheme.col("bg"), _pal)
	if _back_shader == null:
		_back_shader = Shader.new()
		_back_shader.code = BACK_SHADER
		_line_shader = Shader.new()
		_line_shader.code = LINE_SHADER
	_back = ColorRect.new()
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = _back_shader
	_back.material = _mat
	U.full_rect(_back)
	add_child(_back)
	_set_colors()
	# Alles in der Mitte (Hülle, Hof, Logo, Titel) in einer Ebene: beim Abgeben wächst sie leicht.
	_mid = Control.new()
	_mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_mid)
	add_child(_mid)
	_front_shadow = Panel.new()
	_front_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UzTheme.box(Color(0, 0, 0, 0.9), 14)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 46
	sb.shadow_offset = Vector2(0, 18)
	_front_shadow.add_theme_stylebox_override("panel", sb)
	_front_shadow.visible = false
	_mid.add_child(_front_shadow)
	_front = U.rounded_image(14)
	_front.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_front.visible = false
	_mid.add_child(_front)
	_glow = _plain_rect()
	_glow.modulate = Color(0, 0, 0, 0.0)
	_mid.add_child(_glow)
	_logo = _plain_rect()
	_logo.modulate.a = 0.0
	_mid.add_child(_logo)
	_title = U.label(Library.display_title(game), "hero", "text", "black", true)
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Name des Spiels
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.max_lines_visible = 2
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.32))
	_title.add_theme_constant_override("shadow_offset_y", 4)
	_title.add_theme_constant_override("shadow_outline_size", 14)
	_title.modulate.a = 0.0
	_title.visible = false
	_mid.add_child(_title)
	_bottom = U.vbox(0)
	_bottom.alignment = BoxContainer.ALIGNMENT_BEGIN
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bottom)
	var lc := CenterContainer.new()
	lc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line = ColorRect.new()
	_line.custom_minimum_size = Vector2(240, 2)
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line_mat = ShaderMaterial.new()
	_line_mat.shader = _line_shader
	_line_mat.set_shader_parameter("hi", UzTheme.col("accent"))
	_line.material = _line_mat
	lc.add_child(_line)
	_bottom.add_child(lc)
	_bottom.add_child(U.spacer(0, 22, false))
	_status = U.label(_launch_text, "m", "text", "medium")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate.a = 0.92
	U.shadow(_status, 0.6)
	_bottom.add_child(_status)
	_bottom.add_child(U.spacer(0, 6, false))
	var where := str(sys.get("name", Library.store_name(game, false, "PC")))
	if str(game.get("source", "")) == "app":
		where = TranslationServer.translate("Programm" if str((game.get("app", {}) as Dictionary).get("kind", "")) == "prog" else "Store-App")
	_plat = U.label(where, "s", "muted", "medium")
	_plat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	U.shadow(_plat, 0.6)
	_bottom.add_child(_plat)
	_bottom.modulate.a = 0.0
	U.ankommen(_bottom, U.T_ORT, "uz_karte").tween_property(_bottom, "modulate:a", 1.0, U.T_ORT).set_delay(U.NACH_FLAECHE)
	_hint = U.hbox(12)
	_hint.alignment = BoxContainer.ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	add_child(_hint)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.modulate.a = 0.0
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_black)
	add_child(_black)
	_layout()
	get_viewport().size_changed.connect(_on_resized)
	_load_art()


func _set_art_a(v: float) -> void:
	_art_a = v
	_mat.set_shader_parameter("art_a", v)


func _plain_rect() -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Punkt auf Punkt gezeichnet: linear ohne Mipmaps (nie eine kleinere Stufe).
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return t


func _set_colors() -> void:
	_mat.set_shader_parameter("pal", _pal)
	_mat.set_shader_parameter("ground", _ground)
	_mat.set_shader_parameter("view", _view)


# --- Bilder -------------------------------------------------------------------------------------

## Was ohne Internet sofort da ist, kommt gleich; fehlt etwas, holt Media es (Download, SteamGridDB)
## und die Karte blendet es nach, solange sie noch steht.
func _load_art() -> void:
	var missing: Array = []
	for k in ["hero", "logo", "cover", "wide"]:
		var p := Media.local_path(game, k)
		if p != "":
			_paths[k] = p
		else:
			missing.append(k)
	_start_job()
	for k in missing:
		if k == "wide" and _paths.has("cover"):
			continue
		Media.game_file(game, k, func(p: String) -> void:
			if p != "" and is_inside_tree() and not _leaving and not _paths.has(k):
				_paths[k] = p
				_start_job()
		)


func _start_job() -> void:
	if _paths.is_empty():
		_apply({ "mode": "plain" })
		return
	_job = { "m": Mutex.new(), "done": false, "res": null }
	Arbeit.los(Art.prepare.bind(_job, _paths.duplicate(), _view, _pxs))


func _check_job() -> void:
	if _job.is_empty():
		return
	var m: Mutex = _job.m
	m.lock()
	var done := bool(_job.done)
	var res: Variant = _job.res
	m.unlock()
	if done:
		_job = {}
		if res is Dictionary:
			_apply(res)


func _apply(res: Dictionary) -> void:
	_res = res
	info = { "mode": res.get("mode", "plain"), "sizes": res.get("sizes", {}), "up": res.get("up", 0.0),
		"logo_native": res.get("logo_native", Vector2.ZERO), "logo_size": res.get("logo_size", Vector2.ZERO),
		"front_size": res.get("front_size", Vector2.ZERO), "pxs": _pxs }
	if res.has("palette"):
		_pal = (res.palette.vivid as Color)
		_ground = res.palette.ground
		_set_colors()
	if res.has("back_img"):
		var bi: Image = res.back_img
		var tex := ImageTexture.create_from_image(bi)
		info["back_px"] = Vector2(bi.get_size())
		info["back_mips"] = bi.has_mipmaps()
		var was := _art_a
		_mat.set_shader_parameter("art", tex)
		_mat.set_shader_parameter("art_mip", tex)
		_mat.set_shader_parameter("mode", 1)
		_mat.set_shader_parameter("texw", float(bi.get_width()))
		# Ohne großes Bild kommt der Hintergrund schon weich (LaunchArt.vorweich): nicht noch einmal.
		_mat.set_shader_parameter("blur_base", 0.0 if res.mode == "hero" or bool(res.get("vorweich", false)) else 46.0)
		_mat.set_shader_parameter("art_a", minf(was, 0.35))
		create_tween().tween_method(_set_art_a, minf(was, 0.35), 1.0, T_ART)
		if _back_wartet:
			_back_ein()
	if res.has("front_img"):
		_front.texture = ImageTexture.create_from_image(res.front_img)
		_front.visible = true
		_front_shadow.visible = true
		_appear(_front)
		_appear(_front_shadow)
	else:
		_front.visible = false
		_front_shadow.visible = false
	var had_logo := _logo.texture != null
	if res.has("logo_img"):
		_logo.texture = ImageTexture.create_from_image(res.logo_img)
		_glow.texture = ImageTexture.create_from_image(res.glow_img)
		if _title.visible:
			_title.create_tween().tween_property(_title, "modulate:a", 0.0, 0.2)
		if not had_logo:
			_appear(_logo)
			_glow.create_tween().tween_property(_glow, "modulate:a", 0.6, T_LOGO)
	elif not had_logo and not _title.visible:
		_title.visible = true
		_appear(_title)
	if _back_wartet and not res.has("back_img"):
		_back_ein()
	_layout()


## Spielstart aus dem Bild (main_ebenen.gd spielstart_zeigen, nachdem der Hintergrund sein Bild nach
## vorn geholt hat): Die Karte liegt nicht als Ganzes durchsichtig über der Startseite. Ihre Fläche
## blendet erst über das Spielbild, wenn ihr eigenes (scharfes) Bild da ist – bis dahin bleibt das
## Bild des Hintergrunds stehen; ohne Bild nach T_RAUM. Logo, Titel und Stand kommen erst, wenn die
## Oberfläche gegangen ist (T_WEG), eine Spur nach der Fläche: nie zwei Titel zugleich.
func aus_dem_bild() -> void:
	_aus_bild = true
	modulate.a = 1.0
	_back.modulate.a = 0.0
	_mid.modulate.a = 0.0
	_bottom.modulate.a = 0.0
	var spaet := U.T_WEG + U.NACH_FLAECHE
	U.ankommen(_mid, U.T_ORT, "uz_karte").tween_property(_mid, "modulate:a", 1.0, U.T_ORT).set_delay(spaet)
	U.ankommen(_bottom, U.T_ORT, "uz_karte").tween_property(_bottom, "modulate:a", 1.0, U.T_ORT).set_delay(spaet + U.STAFFEL)
	if _mat.get_shader_parameter("mode") == 1:
		_back_ein()
	else:
		_back_wartet = true
		get_tree().create_timer(U.T_RAUM).timeout.connect(func() -> void:
			if _back_wartet and not _res.is_empty():
				_back_ein()
		)


## Die eigene Fläche über das nach vorn gekommene Spielbild (in T_RAUM, Ankommen).
func _back_ein() -> void:
	_back_wartet = false
	if not is_instance_valid(_back):
		return
	U.ankommen(_back, U.T_RAUM, "uz_back").tween_property(_back, "modulate:a", 1.0, U.T_RAUM)


## Die Oberfläche hinter der Karte wieder an ihren Platz (Spielbild, Startseite): beim Zurückkommen,
## solange die Karte deckt, und spätestens wenn sie geht (auch nach einem Fehlstart).
func _oberflaeche_zurueck() -> void:
	if not _aus_bild:
		return
	_aus_bild = false
	var m: Node = get_tree().current_scene if is_inside_tree() else null
	if m == null:
		return
	var bg: Variant = m.get("background")
	if bg is Object and is_instance_valid(bg) and (bg as Object).has_method("zurueck"):
		(bg as Object).call("zurueck")
	var sh: Variant = m.get("shell")
	if sh is Control and is_instance_valid(sh):
		U.stop(sh as Control, "uz_spielstart")
		(sh as Control).modulate.a = 1.0
		(sh as Control).scale = Vector2.ONE


func _exit_tree() -> void:
	_oberflaeche_zurueck()


## Weich aufsteigen: einblenden und von 96,5 % auf volle Größe (danach genau Punkt auf Punkt).
func _appear(c: Control) -> void:
	c.modulate.a = 0.0
	c.scale = Vector2(0.965, 0.965)
	var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, T_LOGO * 0.8)
	tw.tween_property(c, "scale", Vector2.ONE, T_LOGO)


func _on_resized() -> void:
	_view = get_viewport_rect().size
	_set_colors()
	_layout()


## Auf ganze Bildschirmpunkte runden (Logo und Hülle Punkt auf Punkt).
func _snap(v: Vector2) -> Vector2:
	return (v * _pxs).floor() / _pxs


func _layout() -> void:
	var mode := str(_res.get("mode", "plain"))
	var cy := _view.y * 0.45
	if _res.has("band"):
		var b: Rect2 = _res.band
		_mat.set_shader_parameter("band", Vector4(b.position.x, b.position.y, b.size.x, b.size.y))
		_mat.set_shader_parameter("edges", Vector4(
			1.0 if b.position.x > 0.5 else 0.0, 1.0 if b.position.y > 0.5 else 0.0,
			1.0 if b.end.x < _view.x - 0.5 else 0.0, 1.0 if b.end.y < _view.y - 0.5 else 0.0))
		_mat.set_shader_parameter("feather", clampf(b.size.y * 0.1, 36.0, 110.0))
	var below := 0.0
	var lsz: Vector2 = _res.get("logo_size", Vector2.ZERO)
	if _logo.texture == null:
		var w := minf(1500.0, _view.x - 200.0)
		_title.custom_minimum_size = Vector2(w, 0)
		_title.add_theme_font_size_override("font_size", _title_size(Library.display_title(game), w, mode == "box"))
		_title.size = Vector2(w, 0)
		_title.reset_size()
		lsz = Vector2(w, _title.get_combined_minimum_size().y)
	if mode == "box" and _res.has("front_size"):
		var fs: Vector2 = _res.front_size
		var gap := 40.0
		var total := fs.y + gap + lsz.y
		var top := _snap(Vector2((_view.x - fs.x) * 0.5, cy - total * 0.5))
		_place(_front, top, fs)
		(_front.material as ShaderMaterial).set_shader_parameter("size", fs)
		_place(_front_shadow, top, fs)
		below = top.y + fs.y + gap + lsz.y * 0.5
	else:
		below = cy
	var lpos := _snap(Vector2((_view.x - lsz.x) * 0.5, below - lsz.y * 0.5))
	if _logo.texture != null:
		_place(_logo, lpos, lsz)
		var pad: float = _res.get("glow_pad", 0.0)
		# Der Hof sitzt etwas tiefer: wie ein Schatten von oben.
		_place(_glow, lpos - Vector2(pad, pad) + Vector2(0, lsz.y * 0.04), lsz + Vector2(pad, pad) * 2.0)
	_place(_title, lpos, lsz)
	_bottom.position = Vector2(0, _view.y - 222)
	_bottom.size = Vector2(_view.x, 120)
	_hint.position = Vector2(0, _view.y - 166)
	_hint.size = Vector2(_view.x, 40)


func _place(c: Control, pos: Vector2, sz: Vector2) -> void:
	c.position = pos
	c.size = sz
	c.pivot_offset = sz * 0.5


## Schriftgröße für den gesetzten Titel: groß, aber höchstens zwei Zeilen in der Breite.
func _title_size(t: String, w: float, small: bool) -> int:
	var font := UzTheme.display("black")
	var top := 64 if small else 104
	var fs := top
	while fs > 44:
		var line := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if line <= w or (line <= w * 1.8 and fs <= top * 0.8):
			break
		fs -= 4
	return fs


# --- Ablauf -------------------------------------------------------------------------------------

func set_status(text: String) -> void:
	_launch_text = Art.status_text(text, Library.display_title(game))
	if _note == "" and not _running and is_instance_valid(_status):
		_status.text = _launch_text


func set_running() -> void:
	_running = true
	_note = ""
	# Unter Windows gibt main gleich ab (hand_over): dann kein kurzes „Läuft“ im Ausblenden.
	get_tree().create_timer(0.4).timeout.connect(_show_running)


func _show_running() -> void:
	if _leaving or not _running:
		return
	_status.text = "Läuft"
	_line.create_tween().tween_property(_line, "modulate:a", 0.0, U.T_BASE)
	U.clear(_hint)
	_hint.add_child(U.glyph("guide", 28))
	var l := U.label("Guide: Musik, Freunde, Erfolge, Spielstand, Beenden", "s", "muted", "medium")
	l.clip_text = false
	_hint.add_child(l)
	_hint.modulate.a = 0.0
	_hint.visible = true
	_hint.create_tween().tween_property(_hint, "modulate:a", 1.0, U.T_MOVE)
	_plat.create_tween().tween_property(_plat, "modulate:a", 0.0, U.T_BASE)


## Das Spielfenster ist vorn: in T_OUT auf Schwarz, die Mitte wächst dabei leicht. Danach gibt
## main ab (durchsichtig, minimiert) – zu sehen ist dann das Spiel, nie der Desktop.
func hand_over() -> void:
	_leaving = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_black, "modulate:a", 1.0, T_OUT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_mid, "scale", Vector2(1.035, 1.035), T_OUT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_bottom, "modulate:a", 0.0, T_OUT * 0.7)
	_mid.pivot_offset = _view * Vector2(0.5, 0.45)
	await tw.finished


## Zurück aus dem Spiel: die Karte kommt aus dem Schwarz, „Zurück in Uzai“, dann blendet main
## sie über der neu gebauten Startseite aus.
func returning() -> void:
	_leaving = true
	_running = false
	_note = ""
	_hint.visible = false
	_line.modulate.a = 0.0
	_status.text = "Zurück in Uzai"
	_plat.modulate.a = 1.0
	_bottom.modulate.a = 1.0
	_mid.scale = Vector2.ONE
	_mid.modulate.a = 1.0
	_back.modulate.a = 1.0
	_oberflaeche_zurueck()
	if _black.modulate.a > 0.0:
		var tw := create_tween()
		tw.tween_property(_black, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await tw.finished
	if is_inside_tree():
		await get_tree().create_timer(0.16).timeout


## Zurück in Uzai: Die Karte geht über der neu gebauten Startseite. Schrift zuerst (Logo, Titel,
## Hülle und Stand in T_ANTWORT, Kurve „Gehen“), dann kreuzt die Karte selbst in T_WEG mit der
## Startseite darunter (Kurve „Kreuzen“) – der große Titel der Karte steht nie über dem der
## Startseite. Danach gibt sie sich frei.
func gehen() -> void:
	_leaving = true
	for n in [_mid, _bottom, _hint]:
		if is_instance_valid(n) and (n as CanvasItem).visible:
			U.weg(n, "uz_karte").tween_property(n, "modulate:a", 0.0, U.T_ANTWORT)
	var tw := U.kreuzen(self, "uz_karte_weg")
	tw.tween_property(self, "modulate:a", 0.0, U.T_WEG).set_delay(U.T_ANTWORT * 0.5)
	tw.tween_callback(queue_free)


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	_t += dt
	_check_job()
	var k := 1.0 - exp(-_t / KB_TAU)
	_mat.set_shader_parameter("zoom", 1.0 + (Art.KB_ZOOM - 1.0) * k)
	_mat.set_shader_parameter("pan", KB_PAN * k)
	_mat.set_shader_parameter("t", _t)
	if not _running and not _leaving and game.get("source") == "steam" and _t >= _poll_at:
		_poll_at = _t + STEAM_POLL
		_poll_steam()
	if _running and Engine.get_process_frames() % 60 == 0:
		var s := Launcher.elapsed()
		var mins := floori(s / 60.0)
		_status.text = "Läuft seit %d:%02d Std." % [floori(s / 3600.0), mins % 60] if s >= 3600 else "Läuft seit %d Min." % maxi(1, mins)


## Steams appmanifest: überprüft, lädt oder installiert Steam gerade etwas vor dem Start?
func _poll_steam() -> void:
	var appid := int(game.get("appid", 0))
	if appid <= 0 or Library.steam_root() == "":
		return
	if _manifest == "":
		for lib in SteamScanner.library_dirs(Library.steam_root()):
			var p := str(lib).path_join("steamapps/appmanifest_%d.acf" % appid)
			if FileAccess.file_exists(p):
				_manifest = p
				break
		if _manifest == "":
			return
	var st: Variant = VDF.get_ci(VDF.parse_file(_manifest), "AppState", {})
	if st is Dictionary:
		show_note(Art.steam_note(st))


## Hinweis von Steam zeigen (leer: wieder der Startzustand); frac ≥ 0 macht die Leiste zum Balken.
func show_note(n: Dictionary) -> void:
	_note = str(n.get("text", ""))
	_status.text = _note if _note != "" else _launch_text
	_line_mat.set_shader_parameter("frac", float(n.get("frac", -1.0)) if _note != "" else -1.0)

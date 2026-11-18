extends "res://src/ui/layers/layer.gd"
## „Jetzt läuft“ groß (aus dem Guide: A auf das Album im Start oder im Reiter Musik; aus Musik ›
## Läuft gerade): links das Cover groß, darunter Titel, Künstler, Album, Fortschritt und Steuerung;
## rechts der Liedtext von LRCLIB (src/core/lyrics.gd). Mit Zeitangaben läuft er mit – die laufende
## Zeile hell und groß, die anderen leiser, weich im Takt gerollt –, ohne steht er ruhig da, ohne
## Liedtext steht das Cover allein in der Mitte. Dahinter weiche, langsam treibende Farbflächen aus
## dem Cover selbst (stark weichgezeichnet, gedämpft, damit die Schrift lesbar bleibt).
##
## Liegt über allem, auch über dem Spiel (wie die Blätter des Guides). Steuerung: links/rechts
## zwischen Zurück, Pause und Weiter, A drückt; hoch/runter blättert im Liedtext (nach ein paar
## Sekunden folgt er wieder dem Lied); LT/RT Lautstärke der Musik wie im Guide; B zurück.
## „Animationen reduzieren“: nichts treibt, nichts gleitet; leichter Modus: Farbflächen stehen still.

const MusicS := preload("res://src/core/music.gd")
const Lyrics := preload("res://src/core/lyrics.gd")
const Leicht := preload("res://src/core/leicht.gd")

const RECHTS := 0.5             ## der Liedtext beginnt bei diesem Anteil der Breite
const SPALTE_ABSTAND := 34.0    ## Cover bis Titel

var main: Control
var _grund: _Grund
var _inhalt: Control
var _links: Control
var _cover: Control
var _shade: Panel
var _frame: Panel
var _art: TextureRect
var _ph: TextureRect
var _info: VBoxContainer
var _titel: Label
var _kuenstler: Label
var _album: Label
var _bar
var _zeit: Label
var _rest: Label
var _play: Button
var _pegel: HBoxContainer
var _pegel_bar
var _pegel_text: Label
var _pegel_icon: TextureRect
var _text: _Text
var _split := 0.0               ## 0: Cover mittig, 1: Cover links, Liedtext rechts
var _split_v := 0.0
var _split_ziel := 0.0
var _key := "-"
var _art_url := "-"
var _cover_px := 0.0
var _sec := -2
var _bau_frame := -1
var _vol_pending := 0
var _vol_busy := false
var _hints_key := ""


## Öffnet die Großansicht (einmal: liegt sie schon oben, bleibt es dabei).
static func zeigen(host: Control) -> void:
	for l in Nav.layers:
		if is_instance_valid(l) and (l as Object).get_script() == load("res://src/ui/layers/jetzt_laeuft.gd"):
			return
	var s = load("res://src/ui/layers/jetzt_laeuft.gd").new()
	host.call("open_layer", s)


func build() -> void:
	depth = false
	dim = 0.92
	if is_instance_valid(_scrim):
		_scrim.color = Color(UzTheme.col("bg"), dim)
	_bau_frame = Engine.get_process_frames()
	_grund = _Grund.new()
	U.full_rect(_grund)
	add_child(_grund)
	_inhalt = Control.new()
	U.full_rect(_inhalt)
	_inhalt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_inhalt)
	_text = _Text.new()
	_inhalt.add_child(_text)
	_links = Control.new()
	_links.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inhalt.add_child(_links)
	_bau_cover()
	_bau_info()
	resized.connect(_lay)
	Music.updated.connect(_refresh)
	_refresh()
	_hinweise()
	_lay()
	set_process(true)


## Seite: der Grund (Farbflächen) kommt zuerst, die Schrift danach (layer.gd).
func flaeche() -> Control:
	return self


func schrift() -> Array:
	return [_inhalt] if is_instance_valid(_inhalt) else []


func _first_focus() -> Control:
	return _play if is_instance_valid(_play) else Nav.default_in(self)


## Schrift der Ansicht: immer hell (der Grund ist dunkel, auch bei hellen Themes).
static func tinte(name := "text", a := 1.0) -> Color:
	var c := UzTheme.col(name)
	if c.get_luminance() < 0.45:
		c = { "text": Color("#F2F2F2"), "muted": Color("#B4B4BC"), "faint": Color("#8A8A94") }.get(name, Color("#F2F2F2"))
	return Color(c, c.a * a)


func _bau_cover() -> void:
	_cover = Control.new()
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_links.add_child(_cover)
	# Schatten auf eigener Fläche (nie auf einem zuschneidenden Knoten, DESIGN.md › Höhenstufen).
	_shade = Panel.new()
	var sb := UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_cover())
	sb.shadow_color = Color(0, 0, 0, UzTheme.shadow_alpha(0.5))
	sb.shadow_size = 48 if not Leicht.active else 24
	sb.shadow_offset = Vector2(0, 22)
	_shade.add_theme_stylebox_override("panel", sb)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.add_child(_shade)
	_frame = Panel.new()
	_frame.add_theme_stylebox_override("panel", UzTheme.box(UzTheme.col("surface_hi"), UzTheme.r_cover()))
	_frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.add_child(_frame)
	_ph = U.icon("music", 96, "faint")
	_ph.modulate.a = 0.5
	_frame.add_child(_ph)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(_art)
	_frame.add_child(_art)


func _bau_info() -> void:
	_info = U.vbox(0)
	_links.add_child(_info)
	_titel = U.label("", "46", "text", "bold", true)
	_titel.add_theme_font_override("font", UzTheme.display("bold"))
	_titel.add_theme_color_override("font_color", tinte())
	_titel.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_titel.max_lines_visible = 2
	_titel.add_theme_constant_override("line_spacing", -6)
	_info.add_child(_titel)
	_info.add_child(U.spacer(0, 4, false))
	_kuenstler = U.ellipsis(U.label("", "l", "muted", "medium"))
	_kuenstler.add_theme_color_override("font_color", tinte("muted"))
	_kuenstler.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_info.add_child(_kuenstler)
	_album = U.ellipsis(U.label("", "s", "faint", "regular"))
	_album.add_theme_color_override("font_color", tinte("faint"))
	_album.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_info.add_child(_album)
	_info.add_child(U.spacer(0, 28, false))
	_bar = ProgressBarUz.new().setup(0.0, "text", 4, 0)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.add_child(_bar)
	var times := U.hbox(0)
	_zeit = U.label("", "cap", "muted", "medium")
	_zeit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # läuft jede Sekunde weiter: nur Zahlen
	_zeit.add_theme_color_override("font_color", tinte("muted"))
	_zeit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	times.add_child(_zeit)
	_rest = U.label("", "cap", "muted", "medium")
	_rest.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_rest.add_theme_color_override("font_color", tinte("muted"))
	times.add_child(_rest)
	var tm := U.margin(0, 8, 0, 0)
	tm.add_child(times)
	_info.add_child(tm)
	_info.add_child(U.spacer(0, 18, false))
	# Steuerung mittig unter dem Cover, Abspielen größer (dieselbe Sprache wie im Guide).
	var ctl := U.hbox(18)
	ctl.alignment = BoxContainer.ALIGNMENT_CENTER
	ctl.set_meta("uz_row", true)
	_info.add_child(ctl)
	var prev := _knopf("prev", 60)
	prev.set_meta("uz_hint_a", "Vorheriger Titel")
	prev.set_meta("uz_key", "jl:prev")
	prev.pressed.connect(func() -> void: Music.previous())
	ctl.add_child(prev)
	_play = _knopf("pause" if bool(Music.now.get("playing", false)) else "play", 76, true)
	_play.set_meta("uz_default", true)
	_play.set_meta("uz_key", "jl:play")
	_play.pressed.connect(func() -> void:
		Music.play_pause()
		_refresh()
	)
	ctl.add_child(_play)
	var nxt := _knopf("next", 60)
	nxt.set_meta("uz_hint_a", "Nächster Titel")
	nxt.set_meta("uz_key", "jl:next")
	nxt.pressed.connect(func() -> void: Music.next())
	ctl.add_child(nxt)
	# Lautstärke (LT/RT): erscheint am Ort, unter der Steuerung, und geht nach kurzer Zeit wieder.
	_info.add_child(U.spacer(0, 14, false))
	_pegel = U.hbox(12)
	_pegel.alignment = BoxContainer.ALIGNMENT_CENTER
	_pegel.modulate.a = 0.0
	_pegel_icon = U.icon("volume", 20, "muted")
	_pegel_icon.modulate = tinte("muted")
	_pegel.add_child(_pegel_icon)
	_pegel_bar = ProgressBarUz.new().setup(0.0, "text", 3, 160)
	_pegel_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pegel.add_child(_pegel_bar)
	_pegel_text = U.label("", "cap", "muted", "medium")
	_pegel_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Zahl bzw. schon übersetzter Satz
	_pegel_text.add_theme_color_override("font_color", tinte("muted"))
	_pegel_text.clip_text = false
	_pegel.add_child(_pegel_text)
	_info.add_child(_pegel)


## Runder Knopf wie im Guide-Reiter Musik: Abspielen als getönte Fläche, die anderen flach.
func _knopf(icon: String, px: int, primary := false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(px, px)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.icon = Icons.tex(icon, int(px * 0.4))
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = false
	U.ruhig(b, "symbol" if primary else "flach", 0)
	return b


# --- Lage ----------------------------------------------------------------------------------------

## Cover so groß, wie es neben dem Liedtext passt; ohne Liedtext steht die Spalte mittig.
func _lay() -> void:
	var w := size.x
	var h := size.y
	if w < 64.0 or h < 64.0 or not is_instance_valid(_links):
		return
	var c := roundf(clampf(minf(h * 0.46, w * 0.27), 220.0, 600.0))
	if c != _cover_px:
		_cover_px = c
		_cover.size = Vector2(c, c)
		_shade.size = Vector2(c, c)
		_frame.size = Vector2(c, c)
		_ph.size = Vector2(96, 96)
		_ph.position = (Vector2(c, c) - _ph.size) * 0.5
		_info.position = Vector2(0, c + SPALTE_ABSTAND)
		_info.custom_minimum_size.x = c
		_info.size = Vector2(c, 0)
	var col_h := c + SPALTE_ABSTAND + _info.get_combined_minimum_size().y
	var x_mitte := (w - c) * 0.5
	var platz := w * RECHTS - UzTheme.GUTTER
	var x_links := UzTheme.GUTTER + maxf(0.0, (platz - c) * 0.5)
	var e := clampf(_split, 0.0, 1.0)
	_links.position = Vector2(roundf(lerpf(x_mitte, x_links, e)), roundf(maxf(56.0, (h - col_h) * 0.5 - 10.0)))
	var tx := w * RECHTS + 24.0
	_text.position = Vector2(roundf(tx + U.weg_px(U.W_ORT) * (1.0 - e)), 0)
	_text.size = Vector2(maxf(240.0, w - UzTheme.GUTTER - tx), h)
	_text.modulate.a = e


func _process(dt: float) -> void:
	var now: Dictionary = Music.now
	var p := Music.progress_ms()
	var dur := int(now.get("duration", 0))
	if is_instance_valid(_bar):
		_bar.set_value(float(p) / float(dur) if dur > 0 else 0.0)
	var sec := floori(p / 1000.0) if not now.is_empty() else -1
	if sec != _sec:
		_sec = sec
		_zeit.text = _mmss(p) if not now.is_empty() else ""
		_rest.text = ("−" + _mmss(maxi(0, dur - p))) if dur > 0 else ""
	# Cover zur Seite bzw. in die Mitte: Feder im Takt der Ebenen, ruhig sofort.
	if absf(_split - _split_ziel) > 0.0005 or absf(_split_v) > 0.0005:
		if U.reduziert():
			_split = _split_ziel
			_split_v = 0.0
		else:
			var s := U.spring_step(_split, _split_v, _split_ziel, dt * U.tempo(), 13.0)
			_split = s.x
			_split_v = s.y
			if absf(_split - _split_ziel) < 0.001 and absf(_split_v) < 0.001:
				_split = _split_ziel
				_split_v = 0.0
		_lay()


static func _mmss(ms: int) -> String:
	var s := maxi(0, floori(ms / 1000.0))
	return "%d:%02d" % [floori(s / 60.0), s % 60]


# --- Stand ---------------------------------------------------------------------------------------

func _refresh() -> void:
	if not is_instance_valid(_titel):
		return
	var now: Dictionary = Music.now
	var leer := now.is_empty() or str(now.get("title", "")) == ""
	_titel.text = tr("Gerade läuft nichts") if leer else str(now.get("title", ""))
	_kuenstler.text = "" if leer else str(now.get("artist", ""))
	_album.text = "" if leer else str(now.get("album", ""))
	_album.visible = _album.text != ""
	var playing := bool(now.get("playing", false)) and not leer
	if is_instance_valid(_play):
		_play.icon = Icons.tex("pause" if playing else "play", 30)
		var hint := "Pause" if playing else "Weiter"
		if str(_play.get_meta("uz_hint_a", "")) != hint:
			_play.set_meta("uz_hint_a", hint)
			if _play.has_focus():
				Nav.focus_moved.emit(_play)
	var key := "" if leer else Lyrics.key_of(str(now.get("title", "")), str(now.get("artist", "")))
	if key != _key:
		_key = key
		_sec = -2
		_laden(now)
	_bild(str(now.get("art", "")))


## Liedtext zum neuen Titel: der alte geht, der neue kommt, sobald er da ist (aus dem Speicher
## sofort). Ohne Liedtext rückt das Cover in die Mitte.
func _laden(now: Dictionary) -> void:
	var key := _key
	_text.leeren()
	if key == "":
		_split_ziel = 0.0
		_hinweise()
		return
	var res: Dictionary = await Lyrics.fetch(str(now.get("title", "")), str(now.get("artist", "")), str(now.get("album", "")), int(now.get("duration", 0)))
	if not is_inside_tree() or _closing or key != _key:
		return
	var ok := str(res.get("state", "")) == "ok"
	if ok:
		_text.setzen(res)
	_split_ziel = 1.0 if ok else 0.0
	# Beim Öffnen (Liedtext schon im Speicher): gleich an seinem Platz, ohne Gleiten.
	if Engine.get_process_frames() == _bau_frame:
		_split = _split_ziel
		_split_v = 0.0
		_lay()
	_hinweise()


## Cover und Farbflächen zum Titel. Ein spät fertiges Bild eines älteren Titels zählt nicht.
func _bild(art: String) -> void:
	if art == _art_url:
		return
	_art_url = art
	if art == "":
		_art.texture = null
		_grund.bild(null)
		return
	var me: WeakRef = weakref(self)
	MusicS.load_art(art, 640, func(tex: Texture2D) -> void:
		var s: Object = me.get_ref()
		if s == null or _art_url != art:
			return
		if tex == null:
			_art_url = "-"
			return
		var sofort := _art.texture == null and Engine.get_process_frames() - _bau_frame < 3
		_art.texture = tex
		if not sofort:
			_art.modulate.a = 0.0
			U.ankommen(_art, U.T_ORT, "uz_art").tween_property(_art, "modulate:a", 1.0, U.T_ORT)
		_grund.bild(tex)
	)


## Tastenzeile: A (vom Knopf), LT/RT Lautstärke, hoch/runter blättern (nur mit Liedtext), B zurück.
func _hinweise() -> void:
	var h: Array = [["lt", ""], ["rt", "Lautstärke"]]
	if is_instance_valid(_text) and _text.hat_text():
		h.append(["ud", "Blättern"])
	var key := str(h)
	if key == _hints_key:
		return
	_hints_key = key
	set_meta("uz_hints", h)
	if is_inside_tree() and Nav.top_layer() == self:
		Nav.focus_moved.emit(Nav.focused())


# --- Steuerung -----------------------------------------------------------------------------------

func nav_dir(dir: String) -> bool:
	if dir == "up" or dir == "down":
		if is_instance_valid(_text):
			_text.blaettern(-1 if dir == "up" else 1)
		return true
	return false


func handle(cmd: String) -> bool:
	match cmd:
		"lt":
			_lautstaerke(-1)
			return true
		"rt":
			_lautstaerke(1)
			return true
	return false


## LT/RT: Lautstärke der Musik in Schritten von 5 (Music.change_volume wie im Guide und in Läuft
## gerade). Schnell hintereinander gedrückt, gehen die Schritte gesammelt hinaus.
func _lautstaerke(d: int) -> void:
	Sfx.play("tick", 1.0 + 0.08 * float(d))
	_vol_pending += 5 * d
	var vor := Music.shown_volume()
	if vor >= 0:
		_pegel_zeigen(clampi(vor + _vol_pending, 0, 100), "")
	if _vol_busy:
		return
	_vol_busy = true
	while _vol_pending != 0:
		var step := clampi(_vol_pending, -100, 100)
		_vol_pending -= step
		var r: Dictionary = await Music.change_volume(step)
		if not is_inside_tree():
			return
		if bool(r.get("ok", false)):
			_pegel_zeigen(int(r.get("level", 0)), "")
		else:
			_vol_pending = 0
			_pegel_zeigen(-1, vol_fail_text(str(r.get("why", "")), str(Music.now.get("device", ""))))
	_vol_busy = false


## Warum sich die Lautstärke nicht ändern ließ (dieselben Sätze wie in Läuft gerade).
static func vol_fail_text(why: String, device: String) -> String:
	match why:
		"keine_musik":
			return "Gerade läuft keine Musik"
		"spotify_fest":
			return ("%s lässt sich hier nicht leiser stellen" % device) if device != "" else "Dieses Spotify-Gerät lässt sich hier nicht leiser stellen"
		"fehler":
			return "Lautstärke gerade nicht erreichbar"
	return "Kein Ton von %s gefunden" % (device if device != "" else "der Musik-App")


func _pegel_zeigen(level: int, fehler: String) -> void:
	if not is_instance_valid(_pegel):
		return
	_pegel_bar.visible = fehler == ""
	_pegel_icon.texture = Icons.tex("volume_down" if level == 0 else "volume", 20)
	if fehler == "":
		_pegel_bar.set_value(level / 100.0)
		_pegel_text.text = "%d %%" % level
	else:
		_pegel_text.text = tr(fehler)
	var tw := U.ankommen(_pegel, U.T_ANTWORT, "uz_pegel")
	tw.tween_property(_pegel, "modulate:a", 1.0, U.T_ANTWORT)
	tw.tween_interval(1.6 if fehler == "" else 2.6)
	tw.tween_property(_pegel, "modulate:a", 0.0, U.T_WEG).set_trans(Tween.TRANS_QUAD)


# --- Grund: Farbflächen aus dem Cover --------------------------------------------------------------

## Das Cover selbst, riesig und weich (kleinste Mip-Stufen), in drei Lagen, die gegeneinander
## treiben und sich langsam drehen; gedämpft und nach rechts hin eine Spur dunkler, damit der
## Liedtext lesbar bleibt. Ein neues Cover blendet in T_LICHT über. Ohne Cover: Graphit mit einem
## Hauch Akzent. Ruhig und im leichten Modus steht es still.
class _Grund extends ColorRect:
	const UU := preload("res://src/ui/u.gd")
	const LeichtG := preload("res://src/core/leicht.gd")
	const CODE := """
shader_type canvas_item;
uniform sampler2D bild_a : filter_linear_mipmap, repeat_disable;
uniform sampler2D bild_b : filter_linear_mipmap, repeat_disable;
uniform float mischen = 0.0;
uniform float zeit = 0.0;
uniform vec2 seiten = vec2(1.7778, 1.0);
uniform vec4 raum : source_color = vec4(0.043, 0.043, 0.051, 1.0);

vec3 flaechen(sampler2D t, vec2 uv, float z) {
	vec2 p = (uv - 0.5) * seiten;
	vec3 c = vec3(0.0);
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float a = z * (0.031 + 0.011 * fi) + fi * 2.09;
		mat2 r = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
		vec2 q = r * p * (0.62 - 0.12 * fi);
		q += 0.16 * vec2(sin(z * 0.11 + fi * 1.7 + q.y * 2.3), cos(z * 0.09 + fi * 2.3 + q.x * 1.9));
		c += textureLod(t, q + 0.5, 5.2 + fi * 0.5).rgb;
	}
	return c / 3.0;
}

void fragment() {
	vec3 c = mix(flaechen(bild_a, UV, zeit), flaechen(bild_b, UV, zeit), mischen);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = max(mix(vec3(l), c, 1.3), vec3(0.0));
	c *= 0.58;
	l = dot(c, vec3(0.299, 0.587, 0.114));
	if (l > 0.36) {
		c *= 0.36 / l;
	}
	vec2 v = (UV - vec2(0.42, 0.5)) * vec2(1.0, 1.15);
	c *= clamp(1.0 - dot(v, v) * 0.95, 0.0, 1.0);
	c *= 1.0 - 0.18 * smoothstep(0.45, 1.0, UV.x);
	c = mix(raum.rgb, c, 0.9);
	float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	c += (n - 0.5) / 255.0;
	COLOR = vec4(c, 1.0);
}
"""
	static var _shader: Shader
	static var _ersatz: Texture2D
	var _mat: ShaderMaterial
	var _zeit := 0.0
	var _a: Texture2D
	var _b: Texture2D

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		color = Color.WHITE
		if _shader == null:
			_shader = Shader.new()
			_shader.code = CODE
		_mat = ShaderMaterial.new()
		_mat.shader = _shader
		material = _mat
		_a = ersatz()
		_b = _a
		_mat.set_shader_parameter("bild_a", _a)
		_mat.set_shader_parameter("bild_b", _b)
		_mat.set_shader_parameter("raum", UzTheme.col("bg") if UzTheme.col("bg").get_luminance() < 0.3 else Color("#0B0B0D"))
		_zeit = randf() * 120.0
		_mat.set_shader_parameter("zeit", _zeit)
		resized.connect(func() -> void: _mat.set_shader_parameter("seiten", Vector2(size.x / maxf(1.0, size.y), 1.0)))
		set_process(not (UU.reduziert() or LeichtG.active))

	func _process(dt: float) -> void:
		_zeit += dt
		_mat.set_shader_parameter("zeit", _zeit)

	## Neues Cover (null: Ersatz) blendet in T_LICHT über das alte.
	func bild(tex: Texture2D) -> void:
		var neu := tex if tex else ersatz()
		if neu == _b:
			return
		_mat.set_shader_parameter("bild_a", _b)
		_a = _b
		_b = neu
		_mat.set_shader_parameter("bild_b", _b)
		_mat.set_shader_parameter("mischen", 0.0)
		var tw := UU.ankommen(self, UU.T_LICHT, "uz_grund")
		tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("mischen", v), 0.0, 1.0, UU.T_LICHT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	## Ohne Cover: Graphit mit einem Hauch Akzent (klein gerechnet, mit Mip-Stufen).
	static func ersatz() -> Texture2D:
		if _ersatz:
			return _ersatz
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		var g := Color("#1C1C21")
		var acc: Color = UzTheme.col("accent")
		for y in 32:
			for x in 32:
				var d1 := Vector2(x - 9, y - 10).length() / 18.0
				var d2 := Vector2(x - 26, y - 24).length() / 22.0
				var c := g.lerp(acc, clampf(1.0 - d1, 0.0, 1.0) * 0.32).lerp(Color("#2A2A30"), clampf(1.0 - d2, 0.0, 1.0) * 0.6)
				img.set_pixel(x, y, c)
		img.generate_mipmaps()
		_ersatz = ImageTexture.create_from_image(img)
		return _ersatz


# --- Liedtext ------------------------------------------------------------------------------------

## Der Liedtext rechts. Mit Zeitangaben: die laufende Zeile groß und hell, die kommenden leiser,
## die vergangenen noch leiser; der Text rollt mit einer kritisch gedämpften Feder (U.spring_step),
## sodass die laufende Zeile auf Höhe ANKER steht. Größe und Helligkeit wechseln weich (T_RAUM).
## Hoch/runter blättert (alle Zeilen etwas heller), nach BLAETTERN_MS folgt er wieder dem Lied.
## Ohne Zeitangaben: ruhig, von oben, blättern rollt. Oben und unten läuft der Text weich aus.
class _Text extends Control:
	const LS := preload("res://src/core/lyrics.gd")
	const UU := preload("res://src/ui/u.gd")
	const FS_GROSS := 52
	const FS_KLEIN := 40
	const FS_RUHIG := 36
	const ABSTAND := 22.0
	const ANKER := 0.40
	const VORLAUF := 200
	const BLAETTERN_MS := 4000
	const RAND_OBEN := 110.0          ## oben frei für die Quelle, darunter läuft der Text aus
	const RAND_UNTEN := 170.0         ## unten frei für die Tastenzeile
	var _zeilen: Array = []           ## [[ms (-1 ohne Zeit), Text]]
	var _synced: Array = []
	var _mit_zeit := false
	var _e := PackedFloat32Array()    ## Betonung je Zeile 0…1
	var _ys := PackedFloat32Array()
	var _cur := -1
	var _scroll := 0.0
	var _vel := 0.0
	var _blatt := -1                  ## gewählte Zeile beim Blättern (-1: folgt dem Lied)
	var _blatt_bis := 0
	var _a := 0.0
	var _a_ziel := 0.0
	var _neu: Dictionary = {}         ## wartet, bis der alte Text gegangen ist
	var _mass := {}
	var _font: Font
	var _gesamt := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		clip_contents = true
		_font = UzTheme.display("bold")
		gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed:
				if e.button_index == MOUSE_BUTTON_WHEEL_UP:
					blaettern(-1)
				elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					blaettern(1)
		)
		resized.connect(func() -> void: _mass.clear())
		set_process(false)

	func hat_text() -> bool:
		return (_a_ziel > 0.0 and not _zeilen.is_empty()) or not _neu.is_empty()

	## Neuer Liedtext (Ergebnis von Lyrics.fetch mit state „ok“).
	func setzen(res: Dictionary) -> void:
		if _a > 0.02 and not _zeilen.is_empty():
			_neu = res
			_a_ziel = 0.0
			set_process(true)
			return
		_neu = {}
		_synced = res.get("synced", [])
		_mit_zeit = not _synced.is_empty()
		_zeilen = []
		if _mit_zeit:
			_zeilen = _synced
		else:
			for l in res.get("plain", PackedStringArray()):
				_zeilen.append([-1, str(l)])
		_e = PackedFloat32Array()
		_e.resize(_zeilen.size())
		_e.fill(0.0)
		_mass.clear()
		_blatt = -1 if _mit_zeit else 0
		_cur = LS.line_at(_synced, Music.progress_ms() + VORLAUF) if _mit_zeit else -1
		if _cur >= 0:
			_e[_cur] = 1.0
		_layout()
		_scroll = _ziel()
		_vel = 0.0
		_a = 0.0
		_a_ziel = 1.0
		set_process(true)

	## Der alte Text geht (Titelwechsel).
	func leeren() -> void:
		_neu = {}
		_a_ziel = 0.0
		if _a <= 0.01:
			_zeilen = []
			_e = PackedFloat32Array()
		set_process(true)

	func blaettern(d: int) -> bool:
		if _zeilen.is_empty():
			return false
		var von := _blatt if _blatt >= 0 else maxi(_cur, 0)
		var n := clampi(von + d * (1 if _mit_zeit else 2), 0, _zeilen.size() - 1)
		if not _mit_zeit:
			n = clampi(n, 0, _letzte_ruhig())
		if n == von and _blatt >= 0:
			return false
		_blatt = n
		_blatt_bis = Time.get_ticks_msec() + BLAETTERN_MS
		set_process(true)
		return true

	## Ohne Zeitangaben: so weit, dass das Ende unten im Bild steht.
	func _letzte_ruhig() -> int:
		var unten := _gesamt - (size.y - RAND_OBEN - RAND_UNTEN)
		for i in _ys.size():
			if _ys[i] >= unten:
				return i
		return maxi(0, _ys.size() - 1)

	func _fs(i: int) -> int:
		if not _mit_zeit:
			return FS_RUHIG
		return int(roundf(lerpf(FS_KLEIN, FS_GROSS, _e[i])))

	func _breite(fs: int) -> float:
		var w := maxf(200.0, size.x - 8.0)
		return w * fs / FS_GROSS if _mit_zeit else w

	## Höhe einer Zeile bei Schriftgröße fs (gemerkt; Leerzeilen sind eine Pause mit drei Punkten).
	func _hoehe(i: int, fs: int) -> float:
		var k := i * 100 + fs
		if _mass.has(k):
			return _mass[k]
		var t := str(_zeilen[i][1])
		var h := fs * 0.9 if t.strip_edges() == "" else _font.get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, _breite(fs), fs).y
		_mass[k] = h
		return h

	func _layout() -> void:
		_ys.resize(_zeilen.size())
		var y := 0.0
		for i in _zeilen.size():
			_ys[i] = y
			y += _hoehe(i, _fs(i)) + ABSTAND
		_gesamt = y

	func _ziel() -> float:
		if _zeilen.is_empty():
			return 0.0
		if not _mit_zeit:
			return _ys[clampi(_blatt, 0, _ys.size() - 1)] - RAND_OBEN
		var i := _blatt if _blatt >= 0 else maxi(_cur, 0)
		return _ys[i] + _hoehe(i, _fs(i)) * 0.5 - size.y * ANKER

	func _process(dt: float) -> void:
		var ruhig := UU.reduziert()
		var tempo := UU.tempo()
		# Blende (Titelwechsel): der alte geht in T_WEG, der neue kommt in T_RAUM.
		var tau := (UU.T_RAUM if _a_ziel > _a else UU.T_WEG) / 3.0
		_a = _a_ziel if absf(_a - _a_ziel) < 0.004 else lerpf(_a, _a_ziel, 1.0 - exp(-dt * tempo / tau))
		if _a_ziel == 0.0 and _a <= 0.01:
			_a = 0.0
			_zeilen = []
			_e = PackedFloat32Array()
			if not _neu.is_empty():
				var n := _neu
				_neu = {}
				setzen(n)
				return
			set_process(false)
			queue_redraw()
			return
		if _mit_zeit:
			_cur = LS.line_at(_synced, Music.progress_ms() + VORLAUF)
			if _blatt >= 0 and Time.get_ticks_msec() > _blatt_bis:
				_blatt = -1
			var k := 1.0 if ruhig else 1.0 - exp(-dt * tempo / (UU.T_RAUM / 3.0))
			for i in _e.size():
				var z := 1.0 if i == _cur else 0.0
				if _e[i] != z:
					_e[i] = z if absf(_e[i] - z) < 0.01 else lerpf(_e[i], z, k)
		_layout()
		var ziel := _ziel()
		if ruhig:
			_scroll = ziel
			_vel = 0.0
		else:
			var s := UU.spring_step(_scroll, _vel, ziel, dt * tempo, UU.SPRING if _blatt >= 0 else UU.SPRING_HOLD)
			_scroll = s.x
			_vel = s.y
		queue_redraw()

	func _draw() -> void:
		if _a <= 0.01 or _zeilen.is_empty() or _ys.size() != _zeilen.size():
			return
		var text_c: Color = UzTheme.col("text") if UzTheme.col("text").get_luminance() > 0.45 else Color("#F2F2F2")
		var h := size.y
		var blatt := _blatt >= 0 and _mit_zeit
		for i in _zeilen.size():
			var fs := _fs(i)
			var hi := _hoehe(i, fs)
			var y := _ys[i] - _scroll
			if y + hi < -20.0 or y > h + 20.0:
				continue
			var a := 0.86
			if _mit_zeit:
				var leise := 0.30 if i > _cur else 0.2
				if blatt:
					leise = 0.62 if i == _blatt else 0.42
				a = lerpf(leise, 1.0, _e[i])
			# Oben und unten weich aus (Kopf und Tastenzeile).
			var mitte := y + hi * 0.5
			a *= smoothstep(RAND_OBEN * 0.6, RAND_OBEN * 1.8, mitte) * smoothstep(RAND_UNTEN * 0.65, RAND_UNTEN * 1.6, h - mitte)
			a *= _a
			if a <= 0.004:
				continue
			var t := str(_zeilen[i][1])
			if t.strip_edges() == "":
				# Pause im Lied: drei Punkte, die laufende wächst mit.
				var r := 4.0 + 2.5 * (_e[i] if _mit_zeit else 0.0)
				for k in 3:
					draw_circle(Vector2(r + 1.0 + k * r * 4.0, y + hi * 0.5), r, Color(text_c, a))
				continue
			draw_multiline_string(_font, Vector2(0, y + _font.get_ascent(fs)), t, HORIZONTAL_ALIGNMENT_LEFT, _breite(fs), fs, -1, Color(text_c, a))
		# Quelle, leise oben (unten liegt die Tastenzeile).
		draw_string(UzTheme.font("medium"), Vector2(0, 58.0), tr("Songtext: LRCLIB"), HORIZONTAL_ALIGNMENT_LEFT, size.x, UzTheme.size("cap"),
				Color(text_c, 0.34 * _a))

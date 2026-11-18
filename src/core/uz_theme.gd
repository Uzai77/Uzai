extends Node
## Farben, Schriften und Maße. Grundlage sind die Grundwerte des Aussehens („Graphit“ mit der
## Marke, src/core/aussehen.gd). Darüber liegen die Einstellungen (Config "theme.*"): Wer
## Farbschema, Akzent, Ecken, Schrift oder Cover selbst wählt, überschreibt den Grundwert;
## „Standard“ (gespeichert als "theme") nimmt ihn.
## Grundregeln stehen in docs/DESIGN.md (Abschnitt „Marke“): matte Graphit-Flächen, weich
## gerundet, ein Cursor (gefüllte Fläche, um Cover ein heller Ring, "focus") und ein Akzent
## ("accent") – Grün nur für Präsenz.
##
## UzTheme ist die einzige Quelle für Farben, Formen, Schrift, Fokus, Hintergrund, Startbild und
## Pop-ups: Bauteile fragen hier (col, box, r_panel, draw_selection, draw_tile_focus,
## focus_scale, bg_param, popup_palette …).

signal rebuilt
## Die Größe der Oberfläche hat sich geändert (kurz nach dem letzten Schritt am Regler): Seiten,
## die ihre Spalten und Breiten nach der Fenstergröße richten, bauen sich neu.
signal layout_changed

const Leicht := preload("res://src/core/leicht.gd")
const Aussehen := preload("res://src/core/aussehen.gd")

const PRESETS := {
	"uzai": { "name": "Graphit Gold", "bg": "#0d0e10", "surface": "#17181b", "surface_hi": "#222327", "line": "#2c2d31",
		"text": "#f3f1ec", "muted": "#a6a49f", "faint": "#77756f", "accent": "#e7c27d", "focus": "#f4efe6" },
	"etikett": { "name": "Etikett", "bg": "#16181c", "surface": "#0f1114", "surface_hi": "#23262c", "line": "#2e3238",
		"text": "#f2f1ec", "muted": "#a7aab0", "faint": "#80848b", "accent": "#ffd23f", "focus": "#ffd23f" },
	"glut": { "name": "Glut", "bg": "#110e0c", "surface": "#1c1714", "surface_hi": "#27201c", "line": "#3a302a",
		"text": "#f7efe7", "muted": "#bcaa9b", "faint": "#806f63", "accent": "#ff8a57", "focus": "#fff3e8" },
	"mitternacht": { "name": "Mitternacht", "bg": "#0a0c12", "surface": "#141821", "surface_hi": "#1e2331", "line": "#2a3042",
		"text": "#eef0f5", "muted": "#9aa1b3", "faint": "#5f6679", "accent": "#7aa2ff", "focus": "#ffffff" },
	"ps2": { "name": "Tiefsee", "bg": "#03040a", "surface": "#0b0e1c", "surface_hi": "#131834", "line": "#1d2449",
		"text": "#e6ebff", "muted": "#8e98c4", "faint": "#58618b", "accent": "#4b6dff", "focus": "#c9d6ff" },
	"graphit": { "name": "Graphit", "bg": "#0e0e10", "surface": "#18181b", "surface_hi": "#232327", "line": "#303035",
		"text": "#f2f2f3", "muted": "#a2a2aa", "faint": "#67676f", "accent": "#e4e4e7", "focus": "#ffffff" },
	"bernstein": { "name": "Bernstein", "bg": "#0f0c08", "surface": "#1a150f", "surface_hi": "#261f16", "line": "#352b1e",
		"text": "#f6eee0", "muted": "#b8a98e", "faint": "#7b6e58", "accent": "#f2b544", "focus": "#ffe2a6" },
	"phosphor": { "name": "Phosphor", "bg": "#060d0a", "surface": "#0e1813", "surface_hi": "#15231c", "line": "#1f3128",
		"text": "#e2f5e9", "muted": "#8eb59f", "faint": "#557464", "accent": "#69e39a", "focus": "#c8ffd8" },
	"kirsche": { "name": "Kirsche", "bg": "#0e090b", "surface": "#1a1115", "surface_hi": "#26191f", "line": "#36232b",
		"text": "#f7ecef", "muted": "#bb9aa4", "faint": "#7d6068", "accent": "#ff5d78", "focus": "#ffd0d9" },
	"papier": { "name": "Papier (hell)", "bg": "#ebe8e1", "surface": "#f6f4ef", "surface_hi": "#ffffff", "line": "#d5d1c7",
		"text": "#1b1a17", "muted": "#5f5b52", "faint": "#8f8a7e", "accent": "#2c5bd8", "focus": "#1b1a17" },
}

const SEMANTIC := {
	"speak": "#4fd68a", "danger": "#e5484d", "danger_text": "#ff9c9e",
	"ok": "#5fd39b", "warn": "#f0c36a", "live": "#ff8a9a", "steam": "#8cbcff", "discord": "#a8a3ff",
	"music": "#5fdc96", "gold": "#e8c15a", "sale": "#a6e07c", "ra": "#f2b544",
}
## Der frühere Gold-Akzent (Farbschema „Graphit Gold“, von Hand wählbar; Standard der Marke ist
## das Markenviolett #A47BFF, bis 0.16 Lavendel). Ein paar Stellen haben dazu einen eigenen, fein abgestimmten Goldton
## (ACCENT_FOLLOW); bei jedem anderen Akzent nehmen sie den Akzent (siehe apply()).
const GOLD_ACCENT := Color("#e7c27d")
## "mark": Marke der gewählten Gruppe in den Einstellungen; "ambience": Licht hinter dem Guide,
## solange das Spiel noch keine eigene Farbe geliefert hat.
const ACCENT_FOLLOW := { "mark": Color("#e8c15a"), "ambience": Color(0.85, 0.7, 0.45) }

## Schriftgrößen (px bei 1080p). "cap" ist die kleinste Stufe für Etiketten, Gründe und Zeiten –
## kleiner wird am Fernseher nichts geschrieben.
const SIZE := { "cap": 15, "xs": 16, "s": 19, "m": 22, "l": 27, "xl": 36, "xxl": 54, "hero": 72 }
## Abstände: ein Raster aus 4 px. GUTTER ist der Rand links und rechts (Titel-sicherer Bereich).
const SPACE := { "xxs": 4, "xs": 8, "s": 12, "m": 16, "l": 24, "xl": 32, "xxl": 48, "xxxl": 64 }
const GUTTER := 96
## Höhenstufen (weiche, dunkle Schatten, nie farbig): 0 flach, 1 ruht (Karten, Cover, ruhender
## Hauptknopf), 2 gehoben (Kacheln), 3 schwebt (Seitenleiste, Dialog, Guide).
## a = Deckkraft, s = Weite, y = Versatz. Die helle Auswahl selbst glimmt nur (GLOW).
const ELEVATION := [
	{ "a": 0.0, "s": 0, "y": 0 },
	{ "a": 0.3, "s": 18, "y": 8 },
	{ "a": 0.3, "s": 12, "y": 5 },
	{ "a": 0.55, "s": 56, "y": 22 },
]
## Glimmen um die Auswahl: warmes Licht im Akzent, sehr weich (kein Neon).
const GLOW := { "a": 0.24, "s": 18 }
## Ränder bis zu dieser Deckkraft sind Haarlinien und werden nicht gezeichnet (siehe box()).
const HAIRLINE := 0.12
const CORNERS := { "eckig": 3, "leicht": 10, "rund": 16 }
const COVER_BASE := { "hoch": Vector2(216, 288), "quer": Vector2(400, 188), "quadrat": Vector2(248, 248) }
const COVER_SCALE := { "s": 0.82, "m": 1.0, "l": 1.2 }

var c: Dictionary = {}          # aktuelle Farben als Color
var theme: Theme
var font_regular: Font
var font_medium: Font
var font_bold: Font
var font_black: Font
var font_mono: Font
var font_display: Font          ## Saira schmal, sehr fett: Titel
var font_display_black: Font
var font_ui: Font               ## Saira normal breit: Reiter, Knöpfe, Werte
var font_ui_bold: Font
var font_wide: Font             ## Saira breit: Bezeichnungen im Datenblock
var font_title: Font            ## große Titel (Startseite, Guide)
var radius := 8
var light := false

var _base_font: Font
var _mono_base: Font

## Grundwerte des Aussehens (aussehen.gd): gelten, wo die Einstellungen „Standard“ sagen.
var grund: Dictionary = Aussehen.werte()
var _panel_k := 1.6
var _cover_k := 0.85
var _pill := true
var _glass_k := 1.0
var _solid_a := 0.94
var _shadow_weite := 1.0
## Matte Flächen statt Glas (shape.material), eine Form für alles (shape.strict: feste Rundungen
## der Bauteile höchstens der Kartenradius), Auswahl als gehobene matte Fläche statt der einen
## hellen Fläche (focus.fill).
var _matt := false
var _strict := false
var _cursor_matt := false
## Uzai läuft seit … (ms): Die Not-Taste gilt nur kurz nach dem Start.
var _started_ms := 0
const PANIC_MS := 10000


func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	apply()
	Config.changed.connect(_on_config)
	_build_overlay()


## Werte, die ohnehin bei jeder Verwendung frisch gelesen werden: kein Neuaufbau der Seite.
const LIVE := ["theme.aurora", "theme.sounds", "theme.sound_volume", "theme.boot", "theme.clock_24h",
	"theme.sound_space", "theme.sound_set", "theme.music", "theme.music_track", "theme.system_intro"]
## Nur der Hintergrund hängt davon ab: kein Neuaufbau der ganzen Oberfläche. Jeder Schritt am
## Regler „Abdunklung“ baute sonst alle Bereiche neu (100–185 ms pro Schritt).
const BACKGROUND_ONLY := ["theme.dim", "theme.tint", "theme.motes"]
## Ein Wechsel dieser Werte färbt die ganze Oberfläche um: Sie blendet weich über (crossfade).
const CROSSFADE := ["theme.preset", "theme.corners", "theme.font", "theme.display", "theme.cover_shape", "theme.cover_size", "theme.background",
		"theme.accent"]
signal background_changed


func _on_config(key: String) -> void:
	if key in BACKGROUND_ONLY:
		background_changed.emit()
		return
	# Die Größe der Oberfläche ist nur ein Faktor fürs ganze Fenster: kein Neuaufbau, damit der
	# Regler (auch in der Einrichtung) flüssig bleibt.
	# Damit Raster, Spalten und Seitenleisten zur neuen Größe passen, baut sich die Oberfläche
	# einmal neu, sobald der Regler kurz ruht (LAYOUT_DELAY) – nicht bei jedem Schritt.
	if key == "theme.ui_scale":
		get_tree().root.content_scale_factor = ui_scale()
		_layout_due()
		return
	if key in CROSSFADE:
		crossfade()
	if key.begins_with("theme.") and not key in LIVE:
		apply()


func apply() -> void:
	# Leichter Modus (src/core/leicht.gd): Ecken, Schatten und Glimmen hängen davon ab.
	Leicht.refresh()
	var t: Dictionary = Config.get_value("theme", {})
	var preset_id := str(Config.get_value("theme.preset", "theme"))
	c.clear()
	if PRESETS.has(preset_id):
		var preset: Dictionary = PRESETS[preset_id]
		for k in preset.keys():
			if k != "name":
				c[k] = Color(preset[k])
	else:
		for k in (grund.colors as Dictionary).keys():
			c[k] = grund.colors[k]
	for k in SEMANTIC.keys():
		c[k] = Color(SEMANTIC[k])
	var accent := str(t.get("accent", ""))
	if accent != "" and accent.is_valid_html_color():
		c["accent"] = Color(accent)
	light = c["bg"].get_luminance() > 0.5
	# Helle Schemata: das helle Rot („Entfernen“, Warnzeichen) verschwand auf dem hellen Grund –
	# dort ein tiefes Rot.
	if light:
		c["danger_text"] = (c["danger"] as Color).darkened(0.3)
	c["on_accent"] = text_on(c["accent"])
	if not c.has("focus"):
		c["focus"] = c["text"]
	# "focus" ist die Farbe des Cursors (Ring, Rahmen, Punkte), "sel" die Fläche unter der Auswahl:
	# sonst die eine helle Fläche, im matten Cursor eine gehobene Graphit-Fläche (Schrift bleibt hell).
	# Matt (Marke): heller Graphit, eine Spur zum Akzent getönt – deutlich als Fläche zu sehen,
	# die Schrift darauf bleibt hell.
	c["sel"] = (c["surface_hi"] as Color).lerp(c["text"], 0.13).lerp(c["accent"], 0.07) if str(grund.focus.get("fill", "hell")) == "matt" else c["focus"]
	c["on_focus"] = text_on(c["sel"])
	# Schrift auf der hellen Knopf-Auswahl (U.ruhig: gewählt wird ein Knopf hell).
	c["on_cursor"] = text_on(c["focus"])
	# Formen aus dem Theme (Faktoren für große Flächen und Cover, Pillen, Glas, Schatten).
	var shp: Dictionary = grund.shape
	_panel_k = float(shp.panel)
	_cover_k = float(shp.cover)
	_pill = bool(shp.pill)
	_glass_k = float(shp.glass)
	_solid_a = float(shp.solid)
	_shadow_weite = float(shp.shadow)
	_matt = str(shp.get("material", "glas")) == "matt"
	_strict = bool(shp.get("strict", false))
	_cursor_matt = str(grund.focus.get("fill", "hell")) == "matt"
	# Glasflächen: Weiß (bzw. Schwarz bei hellen Schemata) mit wenig Deckkraft. Matt (Marke,
	# Regel 4 „Kein Glas“): feste Graphit-Flächen mit Haarlinie, der Hintergrund scheint nicht durch.
	var ink: Color = c["text"]
	if _matt:
		c["glass"] = c["surface"]
		c["glass_hi"] = c["surface_hi"]
		c["stroke"] = c["line"]
	else:
		c["glass"] = Color(ink, minf(0.055 * _glass_k, 0.3))
		c["glass_hi"] = Color(ink, minf(0.1 * _glass_k, 0.4))
		c["stroke"] = Color(ink, minf(0.085 * _glass_k, 0.3))
	# Der ruhende Hauptknopf ist Glas wie die anderen Knöpfe, nur etwas kräftiger; sein Zeichen
	# trägt den Akzent. Hell bleibt allein die Auswahl. (Früher: Auswahlfarbe 40 % zum Raum hin
	# gedämpft – am Fernseher eine graue Pille, die wie gedrückt oder abgeschaltet aussah.)
	# Auf hellen Schemata wäre kräftigeres Glas dunkler, also wieder „gedrückt“: dort ruht er
	# als weiße, gehobene Fläche.
	c["primary"] = c["surface_hi"] if light else Color(ink, minf(0.15 * maxf(_glass_k, 1.0), 0.45))
	if _matt and not light:
		c["primary"] = (c["surface_hi"] as Color).lerp(ink, 0.07)
	# Akzent als Schrift- und Symbolfarbe: zu dunkle (bzw. auf hellen Schemata zu helle) Akzente
	# rücken zur Tinte hin, damit Wort und Zeichen vom Sofa aus lesbar bleiben.
	var acc: Color = c["accent"]
	var lum := acc.get_luminance()
	c["accent_ink"] = acc.lerp(ink, 0.4) if (lum < 0.3 if not light else lum > 0.35) else acc
	var gold := acc.is_equal_approx(GOLD_ACCENT)
	for k in ACCENT_FOLLOW.keys():
		c[k] = ACCENT_FOLLOW[k] if gold else acc
	# Hell: ein leichter, warmer Schatten. Mit 0,6 stand um Dialoge ein grauer Hof wie ein Fleck.
	c["shadow"] = Color(0, 0, 0, 1) if not light else Color(0.1, 0.09, 0.06, 0.32)
	var corners := str(t.get("corners", "theme"))
	radius = CORNERS.get(corners, int(shp.radius))
	var fk := str(Config.get_value("theme.font", "theme"))
	_load_fonts(str(grund.fonts.body) if fk == "theme" else fk, str(Config.get_value("theme.font_file", "")), fk == "theme")
	var dk := str(Config.get_value("theme.display", "theme"))
	_load_display(str(grund.fonts.display) if dk == "theme" else dk, dk == "theme")
	theme = _build_theme()
	var root := get_tree().root
	root.theme = theme
	root.content_scale_factor = ui_scale()
	_layout_scale = ui_scale()
	RenderingServer.set_default_clear_color(c["bg"])
	rebuilt.emit()


## Größe der Oberfläche. Die Bereiche sind für 1920 × 1080 logische Pixel gebaut (21:9 wird
## breiter, 4:3 höher, nie kleiner). Größer heißt weniger logischer Platz (150 %: 1280 × 720);
## die Seiten richten sich danach (U.room_w, U.tight): Raster mit weniger Spalten, schmalere
## Spalten, Leisten, die mit der Auswahl gleiten (strip_pan.gd), knappere Abstände, und
## Zweitrangiges tritt zurück. Nach einer Änderung baut sich die Oberfläche neu (layout_changed).
const SCALE_MAX := 1.5
const SCALE_FIT := 1.5          ## bis hierher geprüft ohne Überlauf (tests/probe_aufloesung.gd)


const LAYOUT_DELAY := 0.45
var _layout_timer: SceneTreeTimer
var _layout_scale := -1.0        ## Größe beim letzten Aufbau (gleich geblieben: nichts zu tun)


func _layout_due() -> void:
	if _layout_timer != null:
		_layout_timer.timeout.disconnect(_layout_now)
	_layout_timer = get_tree().create_timer(LAYOUT_DELAY)
	_layout_timer.timeout.connect(_layout_now)


func _layout_now() -> void:
	_layout_timer = null
	if is_equal_approx(_layout_scale, ui_scale()):
		return
	_layout_scale = ui_scale()
	layout_changed.emit()


func ui_scale() -> float:
	return clampf(float(Config.get_value("theme.ui_scale", 1.0)), 0.6, 2.0)


func col(name: String, alpha := 1.0) -> Color:
	var v: Color = c.get(name, Color.MAGENTA)
	v.a *= alpha
	return v


func size(name: String) -> int:
	return SIZE.get(name, 22)


## Abstand aus dem Raster (siehe SPACE), unbekannte Namen geben 16.
func space(name: String) -> int:
	return SPACE.get(name, 16)


## Form und Größe der Cover: eigene Wahl, sonst die des Themes.
func cover_shape() -> String:
	var shape := str(Config.get_value("theme.cover_shape", "theme"))
	return shape if COVER_BASE.has(shape) else str(grund.layout.cover_shape)


func cover_size() -> Vector2:
	var s := str(Config.get_value("theme.cover_size", "theme"))
	if not COVER_SCALE.has(s):
		s = str(grund.layout.cover_size)
	return (COVER_BASE.get(cover_shape(), COVER_BASE["hoch"]) as Vector2) * float(COVER_SCALE.get(s, 1.0))


## Schrift auf einer farbigen Fläche: die dunkle oder die helle Tinte, je nachdem, welche mehr
## Kontrast hat (Leuchtdichte linear gerechnet, wie WCAG). Früher nach Helligkeit über 0,55: Auf
## mittlerem Grau (Ersatz-Hüllen der PlayStation) stand dann Weiß mit Kontrast 3 : 1.
## Auf satten Farben bleibt Weiß, solange Dunkel nicht deutlich gewinnt (bis 1,6-fach bei voller
## Sättigung): Auf sattem Blau und Rot liest sich Weiß besser, als die Zahl sagt – der Akzent von
## „Tiefsee“ und das Warnrot behalten so ihre weiße Schrift.
func text_on(bg: Color) -> Color:
	var l := bg.srgb_to_linear().get_luminance() + 0.05
	# Dunkle Tinte: Leuchtdichte 0,006, helle 0,92.
	var dunkel := l / 0.056
	var hell := 0.97 / l
	return Color("#14120e") if dunkel > hell * lerpf(1.0, 1.6, bg.s) else Color("#f5f6f8")


## Radius für große Flächen (Karten, Guide) und für Cover.
func r_panel() -> int:
	return int(round(radius * _panel_k))


func r_cover() -> int:
	# Leichter Modus: Cover schneiden ihr Bild eckig zu (U.clip_round), die Ecken folgen.
	if Leicht.active:
		return mini(Leicht.COVER_RADIUS, int(round(radius * _cover_k)))
	return int(round(radius * _cover_k))


## Radius einer Pille (Knöpfe, Reiter, Abzeichen): rund, oder ohne Pillen (shape.pill) der Grundradius.
## Aufrufer geben weiter 999 an – box() und draw_selection() rechnen es hier um.
func r_pill() -> int:
	return 999 if _pill else radius


## Runde Form mit festem Halbmesser (runde Symbolknöpfe, Punkte): im eckigen Theme höchstens
## der Grundradius.
func r_round(px: int) -> int:
	return px if _pill else mini(px, radius)


func _r(r: int) -> int:
	if r < 0:
		return radius
	if r >= 900:
		return r_pill()
	# Eine Form für alles (shape.strict): feste Rundungen der Bauteile höchstens der größte Radius
	# des Themes (Karten, Cover) – nichts rundet stärker als eine Karte, außer Pillen.
	return mini(r, r_max()) if _strict else r


## Größter Radius einer Fläche (Karten, Cover) – im strengen Theme die Grenze für feste Rundungen.
func r_max() -> int:
	return maxi(radius, maxi(r_panel(), int(round(radius * _cover_k))))


## Radius für eine Form, wie box() ihn nimmt (−1 Grundradius, ab 900 Pille) – für eigene Zeichnungen.
func rund(r := -1) -> int:
	return _r(r)


## Runde Form, die in jedem Theme rund bleibt: nur für Tastensymbole und Menschen (Avatare).
func round_box(bg: Color, r: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(r)
	sb.anti_aliasing = true
	return sb


## Theme der Marke mit einer Form für alles (shape.strict) – die Bauteile nehmen dann die
## Listen-Sprache (liste.gd) und den ruhigen Knopf (U.ruhig).
func strict() -> bool:
	return _strict


## Cursor der Marke (focus.fill = „matt“): Zeilen gewählt als gehobene matte Fläche ohne Linie,
## Knöpfe hell gefüllt, Cover und Kacheln mit hellem Ring (Stärke focus.frame, Abstand frame_gap).
func cursor_frame() -> bool:
	return _cursor_matt


## Matte, feste Flächen mit Haarlinie statt Glas (shape.material = „matt“, Marke Regel 4)?
func matt() -> bool:
	return _matt


# --- Grundwerte für Bauteile ----------------------------------------------------------------

## Wert für den Hintergrund (stage, fade_x, fade_y, top_dim, shade, aurora, tint, tint_k).
func bg_param(key: String) -> Variant:
	return grund.background[key]


## Art des Hintergrunds: eigene Wahl, sonst der Grundwert.
func bg_mode() -> String:
	var m := str(Config.get_value("theme.background", "theme"))
	return m if m in Aussehen.BG_STYLES else str(grund.background.style)


## Startanimation: eigene Wahl, sonst der Grundwert.
func boot_mode() -> String:
	var m := str(Config.get_value("theme.boot", "theme"))
	return m if m in Aussehen.BOOT_STYLES else str(grund.boot.style)


## Farben der Startanimation (Akzent, Raum) aus den Grundfarben.
func boot_color(key: String) -> Color:
	return col("accent") if key == "accent" else col("bg")


## Spiegelung der Cover im Boden der Startseite.
func reflection() -> bool:
	return bool(grund.layout.reflection)


## Wie stark ein gewähltes Element wächst: base ist das Maß des Bauteils für Graphit (Cover im
## Regal 1,12, Kacheln 1,06), der Grundwert verstärkt oder dämpft es.
func focus_scale(base := 1.12) -> float:
	var k := (float(grund.focus.scale) - 1.0) / 0.12
	return 1.0 + (base - 1.0) * k


## Weite der Schatten (Faktor aus den Grundwerten).
func shadow_weite() -> float:
	return _shadow_weite


## Lichtstreif über gewählten Bildern (im leichten Modus ohnehin aus).
func focus_shine() -> bool:
	return bool(grund.focus.shine)


## Farben der Erfolgs-Pop-ups für die gewöhnliche Art; seltene behalten ihr Metall. Das Licht
## (Ring, erste Zeile) folgt dem Akzent, den der Nutzer gewählt hat.
func popup_palette() -> Dictionary:
	var p: Dictionary = grund.popup
	if c.has("accent") and not (c.accent as Color).is_equal_approx(p.light):
		p = p.duplicate()
		p.light = c.accent
	return p


# --- Schriften ---------------------------------------------------------------

## Grundschrift: kind ist „plex“ (IBM Plex Sans, die Schrift der Marke), „hanken“, „atkinson“,
## „system“ oder „datei“ (eigene Datei aus den Einstellungen). standard: die Stärken kommen aus
## den Grundwerten.
func _load_fonts(kind: String, file: String, standard := false) -> void:
	_mono_base = load("res://assets/fonts/AtkinsonHyperlegibleMono-VF.ttf")
	_base_font = null
	var fw: Dictionary = grund.fonts
	if kind == "datei" and file != "" and FileAccess.file_exists(file):
		var ff := FontFile.new()
		if ff.load_dynamic_font(file) == OK:
			_base_font = ff
	elif kind == "system":
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Segoe UI", "Noto Sans", "DejaVu Sans", "Arial"])
		_base_font = sf
	elif kind == "hanken":
		_base_font = hanken()
	elif kind == "plex":
		_base_font = plex()
	if _base_font == null:
		_base_font = load("res://assets/fonts/AtkinsonHyperlegibleNext-VF.ttf")
	var hk := kind == "hanken"
	var px := kind == "plex"
	var tw := standard and (hk or px)
	# Plex reicht bis 700: Halbfett ist „bold“, Fett „black“.
	font_regular = _weight(_base_font, int(fw.w_regular) if tw else 400)
	font_medium = _weight(_base_font, int(fw.w_medium) if tw else (520 if hk else (500 if px else 560)))
	font_bold = _weight(_base_font, int(fw.w_bold) if tw else (650 if hk else (600 if px else 700)))
	font_black = _weight(_base_font, int(fw.w_black) if tw else (760 if hk else 800))
	font_mono = _weight(_mono_base, 500)


## Schrift für Titel, Reiter, Knöpfe und Zahlen: „plex_condensed“ (die Marke: Titel, Wortmarke
## und Claims in IBM Plex Sans Condensed, Reiter, Knöpfe und Zahlen in IBM Plex Sans),
## „hanken“ (ruhige Groteske), „saira“ (eckig, mit Breitenachse – wie die Verpackungen der
## PS2-Zeit) oder „gleich“ (wie die Grundschrift). Seltene Zeichen kommen aus der Grundschrift.
## standard: Stärken und Laufweite aus den Grundwerten, sonst die für eine eigene Wahl.
func _load_display(kind: String, standard := false) -> void:
	var fw: Dictionary = grund.fonts if standard else Aussehen.TITEL_EIGEN
	if kind == "plex_condensed":
		# Titel schmal und fett; alles, was bedient oder gezählt wird, in Plex Sans (Ziffern von
		# Haus aus tabellarisch: Uhr, Zeiten und Punkte springen nicht).
		var ds := int(fw.display_spacing)
		font_display = plex_condensed(int(fw.w_title), ds)
		font_display_black = plex_condensed(int(fw.w_display_black), ds)
		font_title = plex_condensed(int(fw.w_title), int(fw.title_spacing))
		font_ui = _weight(plex(), int(fw.w_ui))
		font_ui_bold = _weight(plex(), int(fw.w_ui_bold))
		font_wide = _weight(plex(), int(fw.w_wide))
		return
	if kind == "gleich":
		font_display = font_black
		font_display_black = font_black
		font_ui = font_bold
		font_ui_bold = font_bold
		font_wide = font_medium
		font_title = font_black
		return
	if kind == "hanken":
		# Titel etwas enger gesetzt.
		var hb: Font = hanken()
		var ds := int(fw.display_spacing)
		font_display = _weight(hb, int(fw.w_title), ds)
		font_display_black = _weight(hb, int(fw.w_display_black), ds)
		font_title = _weight(hb, int(fw.w_title), int(fw.title_spacing))
		font_ui = _weight(hb, int(fw.w_ui))
		font_ui_bold = _weight(hb, int(fw.w_ui_bold))
		font_wide = _weight(hb, int(fw.w_wide))
		return
	var latin: FontFile = load("res://assets/fonts/Saira-latin.woff2")
	var ext: FontFile = load("res://assets/fonts/Saira-latin-ext.woff2")
	var base := latin.duplicate() as FontFile
	base.fallbacks = [ext, _base_font]
	font_display = _saira(base, 78, 800)
	font_display_black = _saira(base, 74, 880)
	font_ui = _saira(base, 100, 600)
	font_ui_bold = _saira(base, 100, 720)
	font_wide = _saira(base, 120, 600)
	font_title = font_display


func _saira(base: Font, width: int, w: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	var ts := TextServerManager.get_primary_interface()
	fv.variation_opentype = { ts.name_to_tag("wght"): w, ts.name_to_tag("wdth"): width }
	return fv


func display(weight := "bold") -> Font:
	if weight == "title":
		return font_title
	return font_display_black if weight == "black" else font_display


func ui(weight := "ui") -> Font:
	match weight:
		"ui_bold": return font_ui_bold
		"wide": return font_wide
		"title": return font_display
	return font_ui


var _hanken: Font


## Hanken Grotesk (OFL) mit Erweiterung für Ō, ł usw. und Atkinson für den Rest.
func hanken() -> Font:
	if _hanken:
		return _hanken
	var latin: FontFile = load("res://assets/fonts/HankenGrotesk-latin.woff2")
	var ext: FontFile = load("res://assets/fonts/HankenGrotesk-latin-ext.woff2")
	var base := latin.duplicate() as FontFile
	base.fallbacks = [ext, load("res://assets/fonts/AtkinsonHyperlegibleNext-VF.ttf")]
	_hanken = base
	return _hanken


var _plex: Font
var _plex_cond := {}


## IBM Plex Sans (OFL, variabel 100–700) – Bedienung, Fließtext, Zahlen. Seltene Zeichen aus
## Atkinson. Die Ziffern sind von Haus aus gleich breit (tabellarisch).
func plex() -> Font:
	if _plex:
		return _plex
	var base := (load("res://assets/fonts/IBMPlexSans-VF.ttf") as FontFile).duplicate() as FontFile
	base.fallbacks = [load("res://assets/fonts/AtkinsonHyperlegibleNext-VF.ttf")]
	_plex = base
	return _plex


## IBM Plex Sans Condensed (OFL) für Titel, Wortmarke und Claims: feste Schnitte, ab 650 fett,
## darunter halbfett. Fehlende Zeichen aus Plex Sans.
func plex_condensed(w := 700, spacing := 0) -> Font:
	var file := "Bold" if w >= 650 else "SemiBold"
	if not _plex_cond.has(file):
		var ff := (load("res://assets/fonts/IBMPlexSansCondensed-%s.ttf" % file) as FontFile).duplicate() as FontFile
		ff.fallbacks = [plex()]
		_plex_cond[file] = ff
	var fv := FontVariation.new()
	fv.base_font = _plex_cond[file]
	if spacing != 0:
		fv.spacing_glyph = spacing
	return fv


func _weight(base: Font, w: int, spacing := 0) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	var ts := TextServerManager.get_primary_interface()
	fv.variation_opentype = { ts.name_to_tag("wght"): w }
	if spacing != 0:
		fv.spacing_glyph = spacing
	# Systemschrift: Die Stärke wählt den Schnitt (Segoe UI, Segoe UI Semibold, Segoe UI Bold …). Jede Stärke
	# bekommt darum ihre eigene Systemschrift – eine gemeinsame trug die zuletzt gesetzte Stärke (800), und der
	# ganze Text stand fett da.
	if base is SystemFont:
		var eigene := (base as SystemFont).duplicate() as SystemFont
		eigene.font_weight = w
		fv.base_font = eigene
	return fv


func font(weight := "regular") -> Font:
	match weight:
		"ui", "ui_bold", "wide", "title": return ui(weight)
		"medium": return font_medium
		"bold": return font_bold
		"black": return font_black
		"mono": return font_mono
	return font_regular


# --- Theme -------------------------------------------------------------------

func box(bg: Color, r := -1, border := 0, border_color := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(_r(r))
	# Keine hellen Haarlinien: 1-px-Ränder in zarter Tinte wirkten am Fernseher wie weiße Striche
	# an den Kanten, an Rundungen sogar gestrichelt. Flächen trennen sich durch Füllung, Abstand
	# und Schatten; sichtbare Ränder (Auswahl, Farbe) bleiben.
	if border > 0 and border_color.a > HAIRLINE:
		# Marke (matt): eine 1-px-Kontur in Haarlinienfarbe rundherum wirkt am Fernseher wie ein
		# Drahtrahmen. Statt ihrer trägt die Fläche eine Lichtkante oben (Premium-Durchgang,
		# docs/DESIGN.md); kräftigere Ränder (Felder, Farben) bleiben, wie sie sind.
		if _matt and border == 1 and _haarlinie(border_color):
			lichtkante(sb)
		else:
			sb.set_border_width_all(border)
			sb.border_color = solid_border(bg, border_color)
	sb.anti_aliasing = true
	return sb


## Ist das die Haarlinienfarbe des Themes (line bzw. stroke)?
func _haarlinie(col_: Color) -> bool:
	return col_.is_equal_approx(c.get("line", Color.MAGENTA)) or col_.is_equal_approx(c.get("stroke", Color.MAGENTA))


## Lichtkante: eine feine, eine Spur hellere Linie an der Oberkante einer Fläche – Licht von oben,
## wie bei einer echten Taste oder Platte. Sie gibt Flächen Tiefe, ohne sie wie eine Kontur
## einzurahmen (Premium-Durchgang). Deckend gemischt (wie solid_border): keine hellen Pixel an den
## Rundungen. k: Stärke (1 = fein, 0 = keine). Auf hellen Schemata gibt es sie nicht (dort wäre
## „heller“ unsichtbar). Alle anderen Ränder der Box werden dabei abgelegt.
func lichtkante(sb: StyleBoxFlat, k := 1.0) -> StyleBoxFlat:
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	if light or k <= 0.0:
		sb.border_width_top = 0
		return sb
	sb.border_width_top = 1
	sb.border_blend = false
	sb.border_color = kante_farbe(sb.bg_color, k)
	return sb


## Farbe der Lichtkante zu einer Füllung: die Füllung (über dem Raum gerechnet) eine Spur zur
## Tinte hin, deckend. Für eigene Zeichnungen (knopf_stand hält sie beim Überblenden nach).
func kante_farbe(fill: Color, k := 1.0) -> Color:
	var under: Color = c.get("bg", Color.BLACK)
	var base := Color(under.lerp(Color(fill.r, fill.g, fill.b), fill.a), 1.0)
	return Color(base.lerp(c.get("text", Color.WHITE), clampf(KANTE_K * k, 0.0, 1.0)), 1.0)


## Wie weit die Lichtkante zur Tinte rückt (bei k = 1).
const KANTE_K := 0.085
## Lichtkante auf dem Cursor (draw_selection): so viel kräftiger als auf ruhenden Flächen.
const CURSOR_KANTE := 2.2


## Matte Fläche der Marke: Füllung, Lichtkante oben, auf Wunsch eine Höhenstufe (lift) – nie eine
## Kontur. Für Karten, Dialoge, Mitteilungen, Knöpfe und Schilder.
func flaeche(bg: Color, r := -1, stufe := 0, kante := 1.0) -> StyleBoxFlat:
	var sb := box(bg, r)
	lichtkante(sb, kante)
	if stufe > 0:
		lift(sb, stufe)
	return sb


## Material „Kernlicht“ (src/ui/kernlicht.gdshader, docs/DESIGN.md): Schwebende Flächen – Guide,
## Schnellmenü, Seitenleisten, Dialoge – bekommen Licht von oben, einen Hauch Akzent von der
## Lichtquelle, eine weiche Lichtkante und feines Korn statt flachem Grau. Das Licht steht oben über
## der Mitte des Schirms: Eine Leiste links bekommt es von rechts, eine rechts von links, ein Dialog
## von oben – überall dieselbe Lampe (auch während eine Leiste hereingleitet). Gesetzt auf c selbst
## (nur seine StyleBox; Kinder bleiben unberührt). Im leichten Modus nicht (null): dort bleibt die
## schlichte Fläche. staerke: 0 … 1; das Theme kann sie dämpfen (shape.shadow < 1).
func kernlicht(c: Control, staerke := 1.0) -> ShaderMaterial:
	if c == null or Leicht.active or staerke <= 0.0:
		return null
	var m := ShaderMaterial.new()
	m.shader = KERNLICHT
	m.set_shader_parameter("akzent", col("accent"))
	m.set_shader_parameter("tinte", col("text"))
	m.set_shader_parameter("hell", 1.0 if light else 0.0)
	m.set_shader_parameter("staerke", staerke * clampf(_shadow_weite, 0.4, 1.0))
	c.material = m
	var lage := func() -> void:
		if is_instance_valid(c) and c.is_inside_tree():
			_kernlicht_lage(c, m)
	c.item_rect_changed.connect(lage)
	c.tree_entered.connect(lage, CONNECT_DEFERRED)
	lage.call()
	return m


const KERNLICHT := preload("res://src/ui/kernlicht.gdshader")


## Größe, Lage der Lampe (oben über der Mitte des Schirms) und echte Bildpunkte je Einheit.
func _kernlicht_lage(c: Control, m: ShaderMaterial) -> void:
	var sz := c.size
	m.set_shader_parameter("groesse", sz)
	var xf := c.get_global_transform()
	var vp := c.get_viewport_rect().size
	var lampe := xf.affine_inverse() * Vector2(vp.x * 0.5, -vp.y * 0.1)
	var lx := clampf(lampe.x / maxf(sz.x, 1.0), -0.1, 1.1)
	m.set_shader_parameter("licht", Vector2(lx, -0.12))
	var ps := absf((c.get_viewport().get_final_transform() * xf).get_scale().y)
	m.set_shader_parameter("einheit", maxf(ps, 0.25))
	# Eckenradius der Fläche: Licht nur auf ihr, nicht auf dem Schatten in den Ecken (kernlicht.gdshader „rund“).
	var sb := c.get_theme_stylebox("panel") as StyleBoxFlat if c.has_theme_stylebox("panel") else null
	# Der kleinste der vier Radien: Seitenleisten mit nur zwei runden Ecken bleiben, wie sie waren.
	m.set_shader_parameter("rund", float(mini(mini(sb.corner_radius_top_left, sb.corner_radius_top_right),
			mini(sb.corner_radius_bottom_left, sb.corner_radius_bottom_right))) if sb else 0.0)


## Godot (Kompatibilitäts-Renderer) zeichnet halbdurchsichtige Ränder an Rundungen fast weiß:
## helle Pixel in den Ecken. Darum wird die Randfarbe vorab mit der Fläche (bzw. dem Raum
## dahinter) gemischt und deckend gemacht – sieht gleich aus, nur ohne Ecken-Pixel.
func solid_border(bg: Color, border_color: Color) -> Color:
	if border_color.a >= 0.999 or border_color.a <= 0.0:
		return border_color
	var under: Color = c.get("bg", Color.BLACK)
	var fill := Color(under.lerp(Color(bg.r, bg.g, bg.b), bg.a), 1.0)
	return Color(fill.lerp(Color(border_color.r, border_color.g, border_color.b), border_color.a), 1.0)


## Fläche ohne Schatten und ohne Rand: Uzai trennt durch Abstand, nicht durch Material.
func card(bg: Color, r := -1, _shadow := true) -> StyleBoxFlat:
	return box(bg, r)


## Auswahl als Ring: heller Rand direkt an der Kante, außen ein weiches Glimmen im Akzent. Im
## Cursor der Marke der helle Ring mit Abstand (Eingabefelder, Bilder), rund mitlaufend.
func focus_box(r := -1, _gap := 5) -> StyleBoxFlat:
	var rr := _r(r)
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.anti_aliasing = true
	if _cursor_matt:
		var fw := cursor_width()
		var out := fw + cursor_gap()
		sb.set_border_width_all(fw)
		sb.border_color = frame_color()
		sb.set_corner_radius_all(_frame_r(rr, out))
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			sb.set_expand_margin(side, out)
		return sb
	sb.set_border_width_all(3)
	sb.border_color = c["focus"]
	sb.set_corner_radius_all(rr + 3)
	sb.expand_margin_left = 3
	sb.expand_margin_right = 3
	sb.expand_margin_top = 3
	sb.expand_margin_bottom = 3
	sb.shadow_color = Color(c["accent"], 0.32 * _glow_k())
	sb.shadow_size = int(12 * _shadow_k())
	return sb


## Auswahl als Fläche: warmes Hell, die Schrift darauf wird dunkel. Im Cursor der Marke die
## gehobene matte Fläche ohne Linie (die Schrift bleibt hell).
func focus_fill(r := -1) -> StyleBoxFlat:
	var sb := box(c["sel"], r)
	if _cursor_matt:
		cursor(sb)
	return sb


## Der Cursor auf einer Auswahl-Box (Marke, Regel 1: ein Cursor, überall gleich): die gefüllte
## Fläche selbst ist der Cursor – keine Linie, kein Glimmen. Ohne Cursor der Marke bekommt nur der
## Hauptknopf (strong) seinen hellen Rand wie bisher, alles andere bleibt, wie es ist.
func cursor(sb: StyleBoxFlat, strong := false) -> StyleBoxFlat:
	if _cursor_matt:
		sb.set_border_width_all(0)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			sb.set_expand_margin(side, 0)
		sb.shadow_size = 0
		return sb
	if strong:
		sb.set_border_width_all(3)
		sb.border_color = (c["focus"] as Color).lightened(0.5)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			sb.set_expand_margin(side, 3)
	return sb


## Stärke und Abstand des hellen Rings (Cover, Kacheln, Eingabefelder; Theme: focus.frame,
## focus.frame_gap).
func cursor_width() -> int:
	return maxi(int(grund.focus.frame), 2)


func cursor_gap() -> int:
	return int(grund.focus.frame_gap)


## Radius eines Rahmens, der um grow Punkte außen um eine Form mit Radius inner liegt: mitlaufend
## rund (gleicher Abstand rundherum).
func _frame_r(inner: int, grow: int) -> int:
	if inner >= 900:
		return inner
	return inner + grow


## Auswahlring für Cover und Kacheln, t = 0…1 zum Einblenden: heller Ring, Gold-Glimmen.
func focus_ring(t: float, r := -1) -> StyleBoxFlat:
	var sb := focus_box(r_cover() if r < 0 else r)
	sb.border_color = Color(sb.border_color, t)
	if _cursor_matt:
		return sb
	sb.shadow_color = Color(c["accent"], 0.38 * t * _glow_k())
	sb.shadow_size = int(16 * t)
	return sb


## Höhenstufe auf eine Fläche legen (weicher, dunkler Schatten, siehe ELEVATION); t blendet ein.
func lift(sb: StyleBoxFlat, level := 1, t := 1.0) -> StyleBoxFlat:
	var e: Dictionary = ELEVATION[clampi(level, 0, ELEVATION.size() - 1)]
	var sc: Color = c.get("shadow", Color.BLACK)
	sb.shadow_color = Color(sc.r, sc.g, sc.b, float(e.a) * sc.a * clampf(t, 0.0, 1.0))
	sb.shadow_size = int(round(float(e.s) * lerpf(0.6, 1.0, clampf(t, 0.0, 1.0)) * _shadow_k() * _shadow_weite))
	sb.shadow_offset = Vector2(0, float(e.y) * clampf(t, 0.0, 1.0) * _shadow_k() * _shadow_weite)
	return sb


## Glimmen als Schatten einer Fläche (warmes Licht im Akzent, ohne Versatz).
func with_glow(sb: StyleBoxFlat, strength := 1.0) -> StyleBoxFlat:
	var s := clampf(strength * _glow_k(), 0.0, 2.0)
	sb.shadow_color = Color(c["accent"], float(GLOW.a) * s)
	sb.shadow_size = int(round(float(GLOW.s) * lerpf(0.7, 1.0, minf(s, 1.0)) * _shadow_k()))
	sb.shadow_offset = Vector2.ZERO
	return sb


## Weite von Schatten und Glimmen: im leichten Modus halb so weit (weniger Fläche zu zeichnen).
static func _shadow_k() -> float:
	return Leicht.SHADOW_K if Leicht.active else 1.0


## Stärke des Glimmens im Theme (0 = kein farbiges Licht um die Auswahl). Bauteile mit eigenem
## Glimmen nehmen es mal glow_k().
func glow_k() -> float:
	return float(grund.focus.glow)


func _glow_k() -> float:
	return glow_k()


## Deckkraft für eigene dunkle Schatten von Bauteilen: im hellen Theme zarter, im flachen Theme
## (shape.shadow < 1) schwächer.
func shadow_alpha(a: float) -> float:
	return a * minf(_shadow_weite, 1.0) * (0.45 if light else 1.0)


## Die helle Auswahlfläche vollständig zeichnen: warmes Glimmen, darauf die helle Fläche.
## t = 0…1 blendet beides gemeinsam ein. Für Zeilen, Pillen und Reiter (siehe U.draw_focus).
## Kein dunkler Schatten: auf hellen Flächen (Seitenleiste) säße er als schmutziger Rand.
## Die beiden Boxen werden wiederverwendet: draw_style_box legt die Form sofort an, danach darf
## sich die Box ändern. Früher entstanden bei jeder Zeichnung (auch in Einblend-Animationen,
## jedes Bild) zwei neue StyleBoxen.
## Hat das Theme einen Rahmen (focus.frame), liegt er mit etwas Abstand außen um die Fläche.
var _sel_glow: StyleBoxFlat
var _sel_fill: StyleBoxFlat
var _sel_frame: StyleBoxFlat


func draw_selection(ci: CanvasItem, rect: Rect2, r := -1, t := 1.0, glow_strength := 1.0) -> void:
	if t <= 0.01:
		return
	var rad := _r(r)
	# Ohne Pillen (shape.pill) wird auch eine Pille mit festem Halbmesser (halbe Höhe) zur Fläche
	# mit Grundradius.
	if not _pill and rad > radius and rad * 2.0 >= minf(rect.size.x, rect.size.y) - 2.0:
		rad = radius
	if glow_strength > 0.0 and _glow_k() > 0.0 and not _cursor_matt:
		if _sel_glow == null:
			_sel_glow = StyleBoxFlat.new()
			_sel_glow.anti_aliasing = true
		_sel_glow.bg_color = Color(0, 0, 0, 0)
		_sel_glow.set_corner_radius_all(rad)
		with_glow(_sel_glow, glow_strength * clampf(t, 0.0, 1.0))
		ci.draw_style_box(_sel_glow, rect)
	if _sel_fill == null:
		_sel_fill = StyleBoxFlat.new()
		_sel_fill.anti_aliasing = true
	var fc: Color = c["sel"]
	_sel_fill.bg_color = Color(fc, fc.a * clampf(t, 0.0, 1.0))
	_sel_fill.set_corner_radius_all(rad)
	# Cursor der Marke: eine gehobene Platte im selben Licht wie die Flächen (Kernlicht) – oben eine
	# feine Lichtkante, eine Spur kräftiger als auf ruhenden Flächen. Keine Kontur rundherum.
	if _cursor_matt and not light:
		_sel_fill.border_width_top = 1
		_sel_fill.border_blend = false
		_sel_fill.border_color = Color(kante_farbe(fc, CURSOR_KANTE), fc.a * clampf(t, 0.0, 1.0))
	else:
		_sel_fill.border_width_top = 0
	ci.draw_style_box(_sel_fill, rect)
	# Cursor der Marke: die Fläche ist der Cursor, keine Linie darum.
	var fw := 0 if _cursor_matt else int(grund.focus.frame)
	if fw > 0:
		if _sel_frame == null:
			_sel_frame = StyleBoxFlat.new()
			_sel_frame.draw_center = false
			_sel_frame.anti_aliasing = true
		var gap := float(grund.focus.frame_gap)
		_sel_frame.set_border_width_all(fw)
		_sel_frame.border_color = Color(frame_color(), clampf(t, 0.0, 1.0))
		_sel_frame.set_corner_radius_all(_frame_r(rad, int(gap) + fw))
		ci.draw_style_box(_sel_frame, rect.grow(gap + fw))


## Farbe des Fokus-Rahmens (Theme: Akzent, Auswahl oder Schrift).
func frame_color() -> Color:
	return col(str(grund.focus.frame_color))


## Auswahl auf Cover und Kacheln (cover_card, Kacheln, Karten): zartes Band im Akzent, darauf der
## helle Ring direkt an der Kante, im Theme mit eigenem Rahmen. t = 0…1 blendet ein. Die drei
## Boxen werden wiederverwendet (wie draw_selection).
var _tile_band: StyleBoxFlat
var _tile_ring: StyleBoxFlat
var _tile_halo: StyleBoxFlat
const TILE_EDGE_W := 2        ## feine Lichtkante auf Cover und Kacheln
const TILE_EDGE_A := 0.45
const TILE_GLOW_A := 0.2       ## soft accent glow around it (kept low; a stronger glow looked too heavy)
const TILE_GLOW_S := 18
## Mouse over a tile or tab (schweben.gd, zeiger_schweben; draw_tile_hover): light edge and a strong accent glow,
## more visible than the selection glow, since a weaker one is too faint to notice with a mouse.
const HOVER_EDGE_A := 0.85
const HOVER_GLOW_A := 0.55
const HOVER_GLOW_S := 26
var _hover_box: StyleBoxFlat


## Schein unter der Maus (t = 0…1). fill: Fläche darin (Reiter oben: Glas), sonst nur Kante und Schein.
func draw_tile_hover(ci: CanvasItem, rect: Rect2, rc: int, t: float, fill := Color(0, 0, 0, 0)) -> void:
	if t <= 0.01:
		return
	if _hover_box == null:
		_hover_box = StyleBoxFlat.new()
		_hover_box.anti_aliasing = true
	_hover_box.draw_center = fill.a > 0.0
	_hover_box.bg_color = Color(fill, fill.a * t)
	_hover_box.set_border_width_all(TILE_EDGE_W)
	_hover_box.border_color = Color(col("accent").lerp(frame_color(), 0.4), HOVER_EDGE_A * t)
	_hover_box.set_corner_radius_all(rc)
	_hover_box.shadow_color = Color(col("accent"), HOVER_GLOW_A * t)
	_hover_box.shadow_size = 0 if Leicht.active else int(round(HOVER_GLOW_S * lerpf(0.6, 1.0, t)))
	ci.draw_style_box(_hover_box, rect)


## Reiter oben unter der Maus (tab_strip.gd): derselbe Schein, darin leises Glas.
func draw_hover(ci: CanvasItem, rect: Rect2, rc: int, t: float) -> void:
	draw_tile_hover(ci, rect, rc, t, Color(col("glass_hi"), 0.9))


func draw_tile_focus(ci: CanvasItem, rect: Rect2, rc: int, t: float) -> void:
	if t <= 0.01:
		return
	if _cursor_matt:
		_draw_tile_ring(ci, rect, rc, clampf(t, 0.0, 1.0))
		return
	var band_k := float(grund.focus.band)
	if band_k > 0.0:
		if _tile_band == null:
			_tile_band = StyleBoxFlat.new()
			_tile_band.draw_center = false
			_tile_band.set_border_width_all(6)
			for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
				_tile_band.set_expand_margin(side, 9)
			_tile_band.anti_aliasing = true
		_tile_band.border_color = Color(col("accent"), 0.24 * t * band_k)
		_tile_band.set_corner_radius_all(rc + 9)
		ci.draw_style_box(_tile_band, rect)
	var ring := int(grund.focus.ring)
	if ring > 0:
		if _tile_ring == null:
			_tile_ring = StyleBoxFlat.new()
			_tile_ring.draw_center = false
			_tile_ring.anti_aliasing = true
		_tile_ring.set_border_width_all(ring)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			_tile_ring.set_expand_margin(side, ring)
		_tile_ring.set_corner_radius_all(rc + ring)
		_tile_ring.border_color = Color(col("focus"), t)
		ci.draw_style_box(_tile_ring, rect)
	var fw := int(grund.focus.frame)
	if fw > 0:
		if _sel_frame == null:
			_sel_frame = StyleBoxFlat.new()
			_sel_frame.draw_center = false
			_sel_frame.anti_aliasing = true
		var gap := float(grund.focus.frame_gap) + ring
		_sel_frame.set_border_width_all(fw)
		_sel_frame.border_color = Color(frame_color(), t)
		_sel_frame.set_corner_radius_all(_frame_r(rc, int(gap) + fw))
		ci.draw_style_box(_sel_frame, rect.grow(gap + fw))


## Brand cursor on covers and tiles: subtle instead of a thick white frame, which looked cheap. A fine
## light edge directly on the border, around it a soft accent glow; the tile's lift and deeper shadow
## do the rest. Light mode: the edge only.
func _draw_tile_ring(ci: CanvasItem, rect: Rect2, rc: int, t: float) -> void:
	if _tile_halo == null:
		_tile_halo = StyleBoxFlat.new()
		_tile_halo.draw_center = false
		_tile_halo.anti_aliasing = true
	_tile_halo.set_border_width_all(TILE_EDGE_W)
	_tile_halo.border_color = Color(frame_color(), TILE_EDGE_A * t)
	_tile_halo.set_corner_radius_all(rc)
	if Leicht.active:
		_tile_halo.shadow_size = 0
	else:
		_tile_halo.shadow_color = Color(col("accent"), TILE_GLOW_A * t)
		_tile_halo.shadow_size = int(round(TILE_GLOW_S * lerpf(0.6, 1.0, t)))
	ci.draw_style_box(_tile_halo, rect)


## Haarlinie um ein Feld der Listen-Sprache, mit der Form gerundet (r wie bei box(); fill: Fläche darin).
func draw_hairline(ci: CanvasItem, rect: Rect2, r := -1, fill := Color(0, 0, 0, 0)) -> void:
	# Ausdrücklich eine Haarlinie rundherum (Felder): nicht die Lichtkante, die box() in der Marke
	# aus einer Haarlinien-Kontur macht.
	var sb := box(fill, r)
	sb.set_border_width_all(1)
	sb.border_color = solid_border(fill, c["line"])
	sb.draw_center = fill.a > 0.0
	ci.draw_style_box(sb, rect)


## Glasfläche mit feinem Rand (Karten, Leisten, Menüs).
func glass(r := -1, strong := false) -> StyleBoxFlat:
	return box(c["glass_hi"] if strong else c["glass"], r_panel() if r < 0 else r, 1, c["stroke"])


## Feste, fast deckende Fläche für alles, was über dem Spiel liegt (der Guide).
func solid(alpha := 0.94, r := -1) -> StyleBoxFlat:
	var base: Color = c["surface"]
	# Das Theme macht die festen Flächen durchsichtiger (Glas) oder deckender.
	var a := clampf(alpha * _solid_a / 0.94, 0.5, 1.0) if absf(_solid_a - 0.94) > 0.001 else alpha
	return box(Color(base.r, base.g, base.b, a), r_panel() if r < 0 else r, 1, c["stroke"])


func _build_theme() -> Theme:
	var th := Theme.new()
	th.default_font = font_regular
	th.default_font_size = SIZE["m"]

	th.set_color("font_color", "Label", c["text"])

	var normal := box(c["glass_hi"], 999, 1, c["stroke"])
	normal.content_margin_left = 26
	normal.content_margin_right = 26
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(c["text"], 0.16)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = c["sel"].darkened(0.12)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = c["glass"]
	var foc := with_glow(focus_fill(999), 0.85)
	foc.content_margin_left = 26
	foc.content_margin_right = 26
	th.set_stylebox("normal", "Button", normal)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", pressed)
	th.set_stylebox("disabled", "Button", disabled)
	th.set_stylebox("focus", "Button", foc)
	th.set_font("font", "Button", font_ui_bold)
	th.set_font_size("font_size", "Button", SIZE["m"])
	for k in ["font_color", "font_hover_color", "font_hover_pressed_color"]:
		th.set_color(k, "Button", c["text"])
	th.set_color("font_focus_color", "Button", c["on_focus"])
	th.set_color("font_pressed_color", "Button", c["on_focus"])
	th.set_color("font_disabled_color", "Button", c["faint"])
	th.set_color("icon_normal_color", "Button", c["text"])
	th.set_color("icon_focus_color", "Button", c["on_focus"])
	th.set_color("icon_pressed_color", "Button", c["on_focus"])
	th.set_color("icon_hover_color", "Button", c["text"])
	th.set_constant("h_separation", "Button", 12)

	th.set_stylebox("panel", "Panel", box(c["surface"], r_panel()))
	th.set_stylebox("panel", "PanelContainer", box(c["surface"], r_panel()))
	th.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	var le := box(c["surface"], -1, 2, c["line"])
	le.content_margin_left = 18
	le.content_margin_right = 18
	le.content_margin_top = 12
	le.content_margin_bottom = 12
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", focus_box())
	th.set_stylebox("read_only", "LineEdit", le)
	th.set_color("font_color", "LineEdit", c["text"])
	th.set_color("font_placeholder_color", "LineEdit", c["faint"])
	th.set_color("caret_color", "LineEdit", c["focus"])
	th.set_color("selection_color", "LineEdit", c["accent"] * Color(1, 1, 1, 0.35))
	th.set_font("font", "LineEdit", font_regular if str(Config.get_value("theme.font", "theme")) in ["hanken", "plex", "theme"] else font_mono)
	return th


# --- Überblenden und Not-Taste --------------------------------------------------------------

var _overlay: CanvasLayer
var _veil: TextureRect
var _veil_tw: Tween


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 110
	add_child(_overlay)
	_veil = TextureRect.new()
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_veil.stretch_mode = TextureRect.STRETCH_SCALE
	_veil.visible = false
	_overlay.add_child(_veil)


## Weich überblenden: Das jetzige Bild bleibt als Standbild über der Oberfläche liegen, während
## sie sich darunter neu aufbaut, und blendet dann aus. Kein harter Neuaufbau, kein Blitz.
func crossfade(sec := 0.42) -> void:
	if _veil == null or DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var vp := get_viewport()
	var tex := vp.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	_veil.texture = ImageTexture.create_from_image(img)
	_veil.visible = true
	_veil.modulate.a = 1.0
	if _veil_tw and _veil_tw.is_valid():
		_veil_tw.kill()
	_veil_tw = create_tween()
	# Kurz warten: so lange baut die Oberfläche neu auf (main._rebuild wartet ein Bild).
	_veil_tw.tween_interval(0.06)
	_veil_tw.tween_property(_veil, "modulate:a", 0.0, sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_veil_tw.tween_callback(func() -> void:
		_veil.visible = false
		_veil.texture = null
	)


## Not-Taste: Wer kurz nach dem Start LB + RB + Ansicht (View/Back/Select) hält oder
## Strg + Umschalt + T drückt, bekommt Standard-Schrift, -Farben und -Ecken zurück – auch wenn eine
## eigene Wahl (Schriftdatei, Farben) die Oberfläche unlesbar gemacht hätte.
func _input(e: InputEvent) -> void:
	if Time.get_ticks_msec() - _started_ms > PANIC_MS:
		return
	var hit := false
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_T:
		hit = (e as InputEventKey).ctrl_pressed and (e as InputEventKey).shift_pressed
	elif e is InputEventJoypadButton and e.pressed:
		var d := (e as InputEventJoypadButton).device
		hit = Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_SHOULDER) and Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER) \
			and Input.is_joy_button_pressed(d, JOY_BUTTON_BACK)
	if hit:
		panic_reset()


## Standard-Aussehen wiederherstellen (Not-Taste, Uzai-Doktor, Tests).
func panic_reset() -> void:
	var changed := false
	for kv in [["theme.preset", "theme"], ["theme.font", "theme"], ["theme.display", "theme"], ["theme.corners", "theme"], ["theme.accent", ""]]:
		if str(Config.get_value(kv[0], "")) != str(kv[1]):
			Config.set_value(kv[0], kv[1])
			changed = true
	if changed and has_node("/root/Toasts"):
		Toasts.show_toast("Standard-Aussehen", "Farben und Schrift sind wieder Standard (Not-Taste).", "palette", { "ms": 7000 })

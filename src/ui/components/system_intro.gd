extends Control
## Per-system boot animation (roadmap 17): when an emulator game starts, a short console start
## sequence (DAUER 2.6 s) plays over the game start card and then cross-fades softly into the card.
## It only bridges the loading time: the game starts at the same time and nothing waits for it. If the
## game window appears earlier, it ends within ABBRUCH seconds; A or B cancel it.
##
## Every major system has its own sequence: color, material, motion and light evoke switching on the
## console. PS2 glass pillars in a blue depth, GameCube a rolling, folding cube, Dreamcast an orange
## swirl … All of them are drawn by shaders under src/ui/components/intro/ (as they ran up to 0.16.12).
## PS2, GameCube, PlayStation, N64 and Switch also have real 3D scenes (system_buehne.gd, since 0.16.13),
## only with the „3D-Szenen“ option; the shader starts look better and are the default again.
## Everything is an original design (R4): no recreation of the original start screens, no jingles, no
## drawn logos or lettering. Systems without their own sequence get their family's, unknown ones a
## calm Uzai sequence.
##
## At the end the system name appears in Uzai's font, or the real logo, but only via the runtime path
## of badge_logos.gd: badges.real_logos is on and the logo is already in cache/logos (downloaded from
## Wikimedia at runtime, never shipped). Nothing is downloaded here.
##
## Whether it runs: soll(). Only emulator games, setting „Startanimation je System“ (Aussehen:
## An, 3D-Szenen, Aus), never in light mode and never with „Animationen reduzieren“.
## With preview = true it runs silently in a loop through all sequences (preview in the settings).
##
## Direction (the same for all sequences, intro.gdshaderinc): the camera moves in from a slight distance
## and turns in gently, fine dust drifts along in three depths; shortly before the name comes the climax
## (HOEHEPUNKT: the light rises, a sheen sweeps diagonally across the image), the name settles in the
## light (grows from 106 % into its place, a sheen runs over it), and from AUS_AB the camera flies
## through the image while it cross-fades into the game start card.
##
## Sharp at the real resolution: the shaders draw per real pixel (the surface is as large as the
## screen), and _apply_bild tells them in every frame how large a pixel is (bildpunkt, with the UI
## stretch and 4K taken into account), so edges and lines are exactly one pixel soft in 1080p as in 4K.
## The logo is prepared at the size it has on screen and placed on whole pixels.
## Smoothness: the clock only starts once the first frame has been drawn (the shader is compiled in it,
## barely visible); the frame times are logged afterwards.

const Arbeit := preload("res://src/core/arbeit.gd")
const Logos := preload("res://src/core/badge_logos.gd")
const Bildzeiten := preload("res://src/ui/components/bildzeiten.gd")
## Die großen Systeme auf Wunsch als echte 3D-Szenen (system_buehne.gd, Wahl „3d“); sonst der Shader.
const Buehne := preload("res://src/ui/components/system_buehne.gd")

const DAUER := 2.6
const NAME_AB := 1.45            ## Name oder Logo erscheinen, das Bild wird ruhiger
const AUS_AB := 2.15             ## ab hier blendet sie in die Spielstart-Karte über
const ABBRUCH := 0.22            ## so schnell geht sie bei A/B oder wenn das Spiel da ist
const HOEHEPUNKT := 1.36         ## das Licht steht am höchsten, kurz bevor der Name kommt
const GLANZ := preload("res://src/ui/components/intro/name_glanz.gdshader")
const FAMILIEN := {
	"8bit": ["nes", "mastersystem", "atari2600"],
	"16bit": ["snes", "megadrive", "pce"],
	"3d": ["n64", "ps1", "saturn"],
	"handheld": ["gb", "gbc", "gba", "gamegear", "nds", "3ds", "psp", "switch"],
	"disc": ["dreamcast", "ps2", "gc", "xbox", "wii", "ps3", "xbox360", "wiiu"],
	"arcade": ["arcade"],
}
## System -> [Sequenz, Variante]. Kennungen wie in FAMILIEN.
const SEQUENZEN := {
	"ps1": ["ps1", 0], "ps2": ["ps2", 0], "ps3": ["welle", 0], "psp": ["welle", 1],
	"gc": ["gc", 0], "wii": ["wii", 0], "wiiu": ["wii", 1], "n64": ["n64", 0],
	"dreamcast": ["dreamcast", 0], "saturn": ["saturn", 0], "xbox": ["xbox", 0], "xbox360": ["xbox360", 0],
	"snes": ["snes", 0], "pce": ["snes", 1], "megadrive": ["megadrive", 0],
	"nes": ["8bit", 0], "mastersystem": ["8bit", 1], "atari2600": ["8bit", 2],
	"gb": ["gb", 0], "gbc": ["gb", 1], "gamegear": ["gb", 2], "gba": ["gba", 0],
	"nds": ["nds", 0], "3ds": ["nds", 1], "switch": ["switch", 0], "arcade": ["arcade", 0],
}
## Familie -> Sequenz für Systeme einer Familie ohne eigene (neue Einträge in FAMILIEN).
const FAMILIEN_SEQUENZ := { "8bit": "8bit", "16bit": "snes", "3d": "n64", "handheld": "gba", "disc": "welle", "arcade": "arcade" }
const NEUTRAL := "uzai"
const SHADER := {
	"ps1": preload("res://src/ui/components/intro/ps1.gdshader"),
	"ps2": preload("res://src/ui/components/intro/ps2.gdshader"),
	"welle": preload("res://src/ui/components/intro/welle.gdshader"),
	"gc": preload("res://src/ui/components/intro/gc.gdshader"),
	"wii": preload("res://src/ui/components/intro/wii.gdshader"),
	"n64": preload("res://src/ui/components/intro/n64.gdshader"),
	"dreamcast": preload("res://src/ui/components/intro/dreamcast.gdshader"),
	"saturn": preload("res://src/ui/components/intro/saturn.gdshader"),
	"xbox": preload("res://src/ui/components/intro/xbox.gdshader"),
	"xbox360": preload("res://src/ui/components/intro/xbox360.gdshader"),
	"snes": preload("res://src/ui/components/intro/snes.gdshader"),
	"megadrive": preload("res://src/ui/components/intro/megadrive.gdshader"),
	"8bit": preload("res://src/ui/components/intro/8bit.gdshader"),
	"gb": preload("res://src/ui/components/intro/gb.gdshader"),
	"gba": preload("res://src/ui/components/intro/gba.gdshader"),
	"nds": preload("res://src/ui/components/intro/nds.gdshader"),
	"switch": preload("res://src/ui/components/intro/switch.gdshader"),
	"arcade": preload("res://src/ui/components/intro/arcade.gdshader"),
	"uzai": preload("res://src/ui/components/intro/uzai.gdshader"),
}
const HELL := Color("#f3f1ec")
const DUNKEL := Color(0.17, 0.175, 0.19)
## Sequenz -> [Höhe von Name/Logo (Anteil des Schirms), Tinte]: frei vom Hauptmotiv, lesbar.
const SCHRIFT := {
	"ps1": [0.5, DUNKEL], "ps2": [0.5, Color(0.9, 0.94, 1.0)], "welle": [0.3, HELL], "gc": [0.8, Color(0.93, 0.9, 1.0)],
	"wii": [0.45, Color(0.33, 0.35, 0.39)], "n64": [0.75, HELL], "dreamcast": [0.78, Color(0.3, 0.2, 0.14)],
	"saturn": [0.8, Color(0.88, 0.92, 1.0)], "xbox": [0.74, Color(0.85, 1.0, 0.8)], "xbox360": [0.77, Color(0.2, 0.26, 0.16)],
	"snes": [0.28, HELL], "megadrive": [0.66, HELL], "8bit": [0.82, HELL], "gb": [0.72, Color(0.12, 0.19, 0.11)],
	"gba": [0.6, Color(0.2, 0.18, 0.45)], "nds": [0.275, DUNKEL], "switch": [0.86, HELL], "arcade": [0.82, HELL],
	"uzai": [0.7, HELL],
}
## Vorschau: diese Systeme nacheinander ("" = neutrale Sequenz).
const REIHE := ["ps2", "gc", "dreamcast", "ps1", "n64", "wii", "xbox", "xbox360", "ps3", "psp", "saturn", "wiiu", "snes", "megadrive",
	"nes", "gb", "gbc", "gba", "nds", "3ds", "switch", "gamegear", "pce", "arcade", ""]
## „theme“ ist der Standard (an); ein früher gespeichertes „an“ zieht Config beim Laden um.
const MODES := [["theme", "An"], ["3d", "3D-Szenen"], ["aus", "Aus"]]

static var _logo_tex := {}       ## Logo-Schlüssel -> einfarbige Textur (einmal je Sitzung gebaut)

var sequenz_id := NEUTRAL
var variante_nr := 0
var system_id := ""
var name_text := ""
var preview := false
var sys_color := Color(0.55, 0.6, 0.72)
## 3D-Szenen statt Shader für die großen Systeme (Einstellung „3d“; Standard: Shader wie bis 0.16.12).
var mit_3d := false
var _t := 0.0
var _t0 := -1                    ## Startzeit (ms): gezählt wird nach der Uhr, nie länger als DAUER
## Die Uhr (ms). Tests setzen eine eigene ein und prüfen so den Ablauf ohne Wanduhr.
var uhr_ms := Callable(Time, "get_ticks_msec")
var _vor := 0                    ## Bilder vor dem Start der Uhr (das erste übersetzt den Shader)
var _mess := Bildzeiten.new()
var _aus_t := -1.0               ## Abbruch: ab diesem _t weich weg
var _cycle := 0
var _bild: ColorRect
var _mat: ShaderMaterial
var _buehne: Buehne                ## 3D-Szene (PS2, GameCube, PlayStation, N64, Switch), sonst null
var _bild3d: TextureRect         ## ihr Bild
var _schrift: Control
var _logo_key := ""
var _logo_lauf: Arbeit.Auftrag   ## Vorbereitung des Logos im Hintergrund, null wenn keine läuft
var _logo_gefasst := false       ## der zweite Schritt (Größe, Mipmaps) läuft oder ist durch
var _logo_an := -1               ## -1 offen, 0 Name, 1 Logo – entschieden, wenn der Name kommt


## Familie eines Systems ("" = keine der bekannten Familien).
static func familie(system: String) -> String:
	for f in FAMILIEN.keys():
		if system in FAMILIEN[f]:
			return f
	return ""


## Sequenz eines Systems: die eigene, sonst die der Familie, sonst die neutrale.
static func sequenz(system: String) -> String:
	if SEQUENZEN.has(system):
		return str(SEQUENZEN[system][0])
	var f := familie(system)
	return str(FAMILIEN_SEQUENZ.get(f, NEUTRAL))


static func variante(system: String) -> int:
	return int(SEQUENZEN[system][1]) if SEQUENZEN.has(system) else 0


## Logo-Schlüssel, wenn am Ende das echte Logo kommen darf: badges.real_logos an und das Logo
## liegt schon im Cache (cache/logos, badge_logos.gd). Sonst "" – dann steht dort der Name.
static func logo_schluessel(system: String) -> String:
	var key := Logos.source_key(system)
	if key == "" or not Logos.enabled():
		return ""
	return key if FileAccess.file_exists(Logos.cache_path(key)) else ""


## Läuft sie für dieses Spiel? setting: „theme“ (Standard: an), „3d“ oder „aus“.
static func soll(game: Dictionary, setting: String, leicht: bool, ruhig: bool) -> bool:
	if leicht or ruhig or str(game.get("source", "")) != "rom":
		return false
	return setting != "aus"


## 3D-Szenen gewählt? (theme.system_intro = „3d“)
static func drei_d_gewaehlt(setting: String) -> bool:
	return setting == "3d"


func setup(game: Dictionary) -> Control:
	mit_3d = drei_d_gewaehlt(str(Config.get_value("theme.system_intro", "theme")))
	_waehlen(str(game.get("system", "")))
	if not preview:
		_logo_key = logo_schluessel(system_id)
	return self


func _waehlen(system: String) -> void:
	system_id = system
	sequenz_id = sequenz(system)
	variante_nr = variante(system)
	var sys: Dictionary = Config.system(system) if system != "" else {}
	name_text = str(sys.get("name", ""))
	if name_text == "":
		name_text = "Uzai" if system == "" else system.to_upper()
	if str(sys.get("color", "")) != "":
		sys_color = Color(str(sys.color))
	_logo_an = -1
	if _mat:
		_mat.shader = SHADER[sequenz_id]
		_uniforms()
		_buehne_bauen()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	if preview:
		mit_3d = drei_d_gewaehlt(str(Config.get_value("theme.system_intro", "theme")))
		_waehlen(str(REIHE[0]))
	_bild = ColorRect.new()
	_bild.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bild.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER[sequenz_id]
	_bild.material = _mat
	add_child(_bild)
	_bild3d = TextureRect.new()
	_bild3d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bild3d.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bild3d.stretch_mode = TextureRect.STRETCH_SCALE
	_bild3d.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bild3d)
	_buehne_bauen()
	_schrift = Control.new()
	_schrift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_schrift.set_anchors_preset(Control.PRESET_FULL_RECT)
	_schrift.draw.connect(_draw_schrift)
	var gm := ShaderMaterial.new()
	gm.shader = GLANZ
	_schrift.material = gm
	add_child(_schrift)
	_uniforms()
	modulate.a = 0.0
	if not preview:
		var l := get_node_or_null("/root/Launcher")
		if l and l.has_signal("window_ready"):
			l.connect("window_ready", _on_fenster)
		_logo_starten()


func _uniforms() -> void:
	# Systemfarbe als klarer, mittelheller Ton (nur die neutrale Sequenz nutzt sie).
	var s := sys_color.s
	var sc := Color.from_hsv(sys_color.h, clampf(s, 0.3, 0.6) if s > 0.15 else s * 0.5, clampf(sys_color.v, 0.74, 0.9))
	_mat.set_shader_parameter("sys_col", sc)
	_mat.set_shader_parameter("acc_col", UzTheme.col("accent"))
	_mat.set_shader_parameter("variante", float(variante_nr))
	_mat.set_shader_parameter("ruhe_ab", NAME_AB)
	_mat.set_shader_parameter("aus_ab", AUS_AB)
	_mat.set_shader_parameter("dauer", DAUER)
	_mat.set_shader_parameter("hoehepunkt", HOEHEPUNKT)
	_mat.set_shader_parameter("t", _t)


## Abbrechen (A/B, Spielfenster da): in ABBRUCH Sekunden weich weg.
func abbrechen() -> void:
	if preview or _aus_t >= 0.0:
		return
	_aus_t = _t


func _on_fenster(_g: Dictionary) -> void:
	abbrechen()


func _input(event: InputEvent) -> void:
	if preview or _aus_t >= 0.0:
		return
	for a in ["uz_a", "uz_b"]:
		if InputMap.has_action(a) and event.is_action_pressed(a, false, true):
			abbrechen()
			return


## Deckkraft zur Zeit t: kurz ein, ab AUS_AB weich in die Karte, beim Abbruch schnell weg – alles
## mit weichen Kurven (Ein: ease-out, Übergang in die Karte und Abbruch: sine in-out, also ohne
## Ruck am Anfang und am Ende).
func deckkraft(t: float) -> float:
	var ein := clampf(t / 0.16, 0.0, 1.0)
	var a := (1.0 - pow(1.0 - ein, 3.0)) * (1.0 - smoothstep(AUS_AB, DAUER, t))
	if _aus_t >= 0.0:
		a *= 0.5 + 0.5 * cos(PI * clampf((t - _aus_t) / ABBRUCH, 0.0, 1.0))
	return a


## Ist sie vorbei (Zeit um oder abgebrochen und ausgeblendet)?
func vorbei(t: float) -> bool:
	return t >= DAUER or (_aus_t >= 0.0 and t >= _aus_t + ABBRUCH)


func _process(dt: float) -> void:
	_logo_pruefen()
	if preview:
		_t += dt
		if _t > DAUER + 0.35:
			_t = 0.0
			_cycle = (_cycle + 1) % REIHE.size()
			_waehlen(str(REIHE[_cycle]))
		modulate.a = smoothstep(0.0, 0.16, _t) * (1.0 - smoothstep(AUS_AB + 0.1, DAUER + 0.3, _t))
	else:
		# Nach der Uhr, nicht nach Bildern: auch wenn ein langsamer PC beim Spielstart stockt,
		# ist sie nach DAUER vorbei. Die Uhr beginnt nach dem ersten Bild: Darin wird der Shader
		# übersetzt (fast durchsichtig, damit Godot ihn überhaupt zeichnet) – das lange erste Bild
		# frisst so nicht den Anfang der Sequenz.
		var now: int = uhr_ms.call()
		if _t0 < 0:
			_vor += 1
			if _vor >= 2:
				_t0 = now
			modulate.a = 0.01
		else:
			_t = (now - _t0) / 1000.0
			_mess.bild(_t)
			modulate.a = deckkraft(_t)
			if vorbei(_t):
				_mess.melden("Startanimation %s" % sequenz_id)
				queue_free()
				return
	_apply_bild()


## Mit „3D-Szenen“ für die großen Systeme die 3D-Szene bauen (die alte geht), sonst zeichnet der Shader.
func _buehne_bauen() -> void:
	if is_instance_valid(_buehne):
		_buehne.queue_free()
	_buehne = null
	var drei_d := mit_3d and Buehne.hat(sequenz_id)
	if drei_d:
		_buehne = Buehne.new().setup(sequenz_id)
		add_child(_buehne)
		_bild3d.texture = _buehne.textur()
	_bild3d.visible = drei_d
	_bild.visible = not drei_d


## Zeit, Seitenverhältnis und Größe eines echten Bildpunkts an den Shader (bzw. an die 3D-Szene).
func _apply_bild() -> void:
	if is_instance_valid(_buehne):
		_buehne.groesse(Vector2i((size * _pixel_scale()).round()))
		_buehne.stellen(minf(_t, DAUER))
	_mat.set_shader_parameter("t", minf(_t, DAUER))
	_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	_mat.set_shader_parameter("bildpunkt", bildpunkt(size.y * _pixel_scale()))
	var gm := _schrift.material as ShaderMaterial
	if gm:
		gm.set_shader_parameter("lage", name_glanz(minf(_t, DAUER)))
	_schrift.queue_redraw()


## Wo der Glanz über dem Namen steht (Anteil der Breite, −1 = aus): einmal von links nach rechts,
## während der Name sich setzt.
static func name_glanz(t: float) -> float:
	var x := (t - NAME_AB - 0.08) / 0.6
	if x <= 0.0 or x >= 1.0:
		return -1.0
	return lerpf(-0.25, 1.25, 0.5 - 0.5 * cos(PI * x))


## Wie groß der Name ist, während er sich setzt (1,06 → 1, Kurve „Ankommen“).
static func name_mass(a: float) -> float:
	return 1.0 + 0.06 * (1.0 - _ease_out(a))


## Größe eines Bildpunkts in den Einheiten der Shader (ort(): Höhe der Fläche = 2) bei einer Höhe
## von hoehe_px echten Bildpunkten.
static func bildpunkt(hoehe_px: float) -> float:
	return 2.0 / maxf(hoehe_px, 1.0)


## Echte Bildpunkte je Einheit der Oberfläche hier (Streckung, Größe der Oberfläche, Vorschau).
func _pixel_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var xf := get_viewport().get_final_transform() * get_global_transform_with_canvas()
	return maxf(absf(xf.get_scale().y), 0.01)


## Für Proben: einen festen Zeitpunkt zeichnen.
func at_time(t: float) -> void:
	_t = t
	modulate.a = 1.0 if preview else deckkraft(_t)
	if _mat:
		_apply_bild()


# --- Logo (nur aus dem Cache, im Hintergrund vorbereitet) ------------------------------------

func _logo_starten() -> void:
	if _logo_key == "" or _logo_tex.has(_logo_key):
		return
	# Einfärben kostet einige Zehntel Sekunden: nicht im Bild, das gerade das Spiel startet.
	_logo_gefasst = false
	_logo_lauf = Arbeit.auftrag(_logo_vorbereiten.bind(Logos.cache_path(_logo_key)), Arbeit.SOFORT)


static func _logo_vorbereiten(path: String) -> Image:
	var img := Logos.prepare(Logos.load_image(path))
	return Logos.mono(img) if img else null


## Verkleinern und Mipmaps (zweiter Schritt, auch im Hintergrund): Die Höhe steht erst fest, wenn
## die Fläche ihre Größe hat – darum nicht schon in _logo_vorbereiten.
static func _logo_fassen(img: Image, px: int) -> Image:
	if img.get_height() > px:
		var asp := float(img.get_width()) / float(img.get_height())
		img.resize(maxi(1, roundi(px * asp)), px, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return img


func _logo_pruefen() -> void:
	if _logo_lauf == null or not _logo_lauf.fertig:
		return
	var img := _logo_lauf.wert as Image
	_logo_lauf = null
	if img == null or img.is_empty():
		return
	if not _logo_gefasst:
		# So hoch, wie es auf dem Schirm steht (in echten Bildpunkten, 4K eingerechnet): nie
		# hochgerechnet, nur verkleinert.
		_logo_gefasst = true
		var px := logo_hoehe_px(minf(size.x / 1920.0, size.y / 1080.0) if size.y > 10 else 1.0, _pixel_scale())
		_logo_lauf = Arbeit.auftrag(_logo_fassen.bind(img, px), Arbeit.SOFORT)
		return
	_logo_tex[_logo_key] = ImageTexture.create_from_image(img)


## Höhe (echte Bildpunkte), in der das Logo vorbereitet wird: so hoch, wie es höchstens auf dem
## Schirm steht (Logos.line_size: bis 1,4 × 76 Einheiten), k Maßstab der Fläche, ps Bildpunkte je
## Einheit (4K: 2).
static func logo_hoehe_px(k: float, ps: float) -> int:
	return clampi(ceili(76.0 * 1.4 * k * ps), 64, 640)


## Zeigt sie am Ende das Logo? (Entschieden, wenn der Name kommt; danach kein Wechsel.)
func zeigt_logo() -> bool:
	return _logo_key != "" and _logo_tex.has(_logo_key)


# --- Name oder Logo -------------------------------------------------------------------------

func _draw_schrift() -> void:
	var t := minf(_t, DAUER)
	var k := minf(size.x / 1920.0, size.y / 1080.0) * (1.5 if preview else 1.0)
	if t >= NAME_AB - 0.05 and _logo_an < 0:
		_logo_an = 1 if zeigt_logo() else 0
	var a := smoothstep(NAME_AB, NAME_AB + 0.45, t)
	if a > 0.0:
		var sc: Array = SCHRIFT.get(sequenz_id, SCHRIFT[NEUTRAL])
		var ink: Color = sc[1]
		if sequenz_id == "gb" and variante_nr == 2:
			ink = HELL
		var y := size.y * float(sc[0]) + (1.0 - _ease_out(a)) * 16.0 * k
		var breite := 0.0
		# Der Name setzt sich: aus 106 % an seinen Platz (um seine Mitte).
		var ms := name_mass(a)
		_schrift.draw_set_transform(Vector2(size.x * 0.5, y) * (1.0 - ms), 0.0, Vector2(ms, ms))
		if _logo_an == 1:
			var tex: Texture2D = _logo_tex[_logo_key]
			var asp := float(tex.get_width()) / float(maxi(tex.get_height(), 1))
			var sz := Logos.line_size(asp, 76.0 * k, 560.0 * k)
			# Auf ganze echte Bildpunkte gesetzt: kein halber Bildpunkt Versatz, der es weich zeichnet.
			var ps := _pixel_scale()
			var lt := (Vector2(size.x * 0.5 - sz.x * 0.5, y - sz.y * 0.5) * ps).round() / ps
			_schrift.draw_texture_rect(tex, Rect2(lt, (sz * ps).round() / ps), false, Color(ink, a))
			breite = sz.x
			y += sz.y * 0.5
		else:
			var f := UzTheme.display("bold")
			var fs := maxi(int(66.0 * k), 12)
			var txt: String = name_text if system_id != "" or not preview else str(TranslationServer.translate("Eigenes System"))
			var base := y + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5
			_schrift.draw_string(f, Vector2(0, base), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color(ink, a))
			breite = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			y += fs * 0.55
		# Eine feine Linie wächst unter dem Namen: der Moment, in dem die Konsole „steht“.
		var w := breite * 0.32 * _ease_out(smoothstep(NAME_AB + 0.15, NAME_AB + 0.7, t))
		if w > 1.0:
			var ly := y + 18.0 * k
			_schrift.draw_line(Vector2(size.x * 0.5 - w, ly), Vector2(size.x * 0.5 + w, ly), Color(ink, 0.4 * a), maxf(2.0 * k, 1.0), true)
		_schrift.draw_set_transform(Vector2.ZERO)


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)

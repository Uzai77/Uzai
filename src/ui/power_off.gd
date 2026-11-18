extends Control
## Ausschalt-Animation – das Gegenstück zum Start (boot.gd), gut 1,4 s, im Takt des Ausschaltklangs
## (power_off.wav: leiser Druck bei 0, dann fällt es abwärts ab 0,62 s):
##   0,00  Die Oberfläche tritt zurück: wird etwas kleiner, dunkler, ihre Ecken runden sich – ein
##         Bild auf einem Schirm, kein Raum mehr.
##   0,56  Wie bei einem Röhrenfernseher fällt das Bild zu einer hellen Linie zusammen (es wird dabei,
##         je flacher, desto heller wie Leuchtstoff) …
##   0,72  … und die Linie zieht sich zum Punkt zusammen. Ein Lichtpunkt im Akzent –
##         die LED, die noch kurz leuchtet …
##   1,05  … und dann verglimmt. Danach ist alles schwarz.
## Ein Shader (power_off.gdshader) zeichnet das echte Bild der Oberfläche, gestaucht, in echten
## Bildpunkten: Kanten einen Bildpunkt weich, in jeder Auflösung gleich scharf.
## Flüssig: Die Uhr läuft nach der Zeit und beginnt nach dem ersten gezeichneten Bild (der Shader
## wird darin übersetzt, das Bild ist da noch unverändert); Klang und Bild beginnen gemeinsam.
## Die Bildzeiten stehen danach im Protokoll.
##
## Ein zweiter Druck auf A oder B (Enter, Esc, Klick) kürzt ab: schnell schwarz, Klang blendet aus.
## Nie länger als CAP. main entscheidet mit mode_for, ob sie überhaupt läuft (Einstellung
## „Ausschalt-Animation“, Fenster sichtbar), und beendet Uzai nach finished. hold: danach schwarz
## stehen bleiben (Ruhezustand, Neustart, Herunterfahren), reveal() blendet wieder auf.
## „kurz“ (Animationen reduzieren): ohne Bewegung – das Bild blendet ab, der Punkt leuchtet kurz in
## der Mitte und geht aus.
## preview = true: still in Schleife mit einem Ersatzbild (Vorschau in den Einstellungen).

signal finished

const U := preload("res://src/ui/u.gd")
const Bildzeiten := preload("res://src/ui/components/bildzeiten.gd")
const SHADER := preload("res://src/ui/power_off.gdshader")

const LENGTH := 1.4        ## volle Fassung
const SHORT := 0.6         ## „Animationen reduzieren“: nur abblenden, kurz der Punkt
const CAP := 1.6           ## spätestens dann ist Schluss, auch wenn der Klang länger wäre
const SKIP_FADE := 0.16    ## abgekürzt: so schnell wird es schwarz
const SKIP_GUARD := 0.12   ## so lange nach dem Start zählt kein Druck (der Druck, der ausschaltete)
const REVEAL_S := 0.5      ## Wieder an: so lange blendet das Schwarz weich (sine in-out) auf

## Zeitplan (s) der vollen Fassung, im Takt des Klangs (Zusammenfallen: tiefer Ton bei 0,62 s).
const RECEDE := 0.55                 ## Oberfläche tritt zurück: 0 … RECEDE
const SQUASH := Vector2(0.56, 0.72)  ## Bild → Linie
const SHRINK := Vector2(0.72, 0.88)  ## Linie → Punkt
const TO_DOT := Vector2(0.76, 0.92)  ## die Linie wird dicker und nimmt den Akzent an
const GLOW_OUT := Vector2(1.05, 1.32) ## Punkt verglimmt
const BLACK_AT := Vector2(1.3, 1.38) ## alles schwarz
## Halbmesser des Lichtpunkts, zu dem die Röhre zusammenfällt (Einheiten von 1080 Zeilen).
const PUNKT_R := 22.5

## Wege, auf denen Uzai sich selbst schließt oder den PC ausschaltet: hier läuft die Animation.
## Alles andere (zweites Schließen, Windows fährt herunter, ein zweites Uzai, das nur weitergibt)
## beendet sofort.
const REASONS := ["quit", "quit_full", "hung", "wm_close", "sleep", "restart", "shutdown"]

var mode := "voll"          ## voll | kurz
var preview := false
var hold := false
var _t := 0.0
var _done := false
var _skip_at := -1.0
var _skip_black := 0.0
var _player: AudioStreamPlayer
var _vol0 := 0.0
var _start_ms := 0
var _t0_us := -1             ## Start der Uhr (nach dem ersten Bild)
var _frozen := false
var _screen: ColorRect
var _mat: ShaderMaterial
var _mess := Bildzeiten.new()


# --- Reine Logik (tests/logic_system.gd) ---------------------------------------------------

## Wie Uzai sich verabschiedet: "voll", "kurz" (Animationen reduzieren) oder "aus" (sofort).
## enabled: Einstellung „Ausschalt-Animation“; shown: das Fenster ist zu sehen (window_shown).
static func mode_for(reason: String, enabled: bool, shown: bool, reduced := false) -> String:
	if not reason in REASONS or not enabled or not shown:
		return "aus"
	return "kurz" if reduced else "voll"


## Ist Uzais Fenster überhaupt zu sehen? Minimiert, versteckt, im Spiel geparkt oder als
## durchsichtige Ebene über einem Spiel/Video: keine Animation, sofort beenden.
static func window_shown(visible: bool, win_mode: int, headless: bool, parked := false, overlay := false) -> bool:
	return visible and not headless and not parked and not overlay and win_mode != Window.MODE_MINIMIZED


## Wie lange das Beenden höchstens hinausgezögert wird (Klanglänge sound_len eingerechnet).
static func delay_for(m: String, sound_len: float) -> float:
	match m:
		"aus":
			return 0.0
		"kurz":
			return clampf(maxf(SHORT, sound_len), SHORT, CAP)
	return clampf(maxf(LENGTH, sound_len), LENGTH, CAP)


## Kürzt dieser Druck ab? A oder B am Controller, Enter, Leertaste, Esc oder ein Klick.
static func is_skip(e: InputEvent) -> bool:
	if e is InputEventJoypadButton:
		var b := e as InputEventJoypadButton
		return b.pressed and b.button_index in [JOY_BUTTON_A, JOY_BUTTON_B]
	if e is InputEventKey:
		var k := e as InputEventKey
		return k.pressed and not k.echo and k.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE, KEY_BACKSPACE]
	if e is InputEventMouseButton:
		var m := e as InputEventMouseButton
		return m.pressed and m.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
	return false


## Vorschau für die Einstellungen (wie die der Startanimation): das Zeichen fällt still in
## Schleife zusammen; aus: ein Satz, was stattdessen passiert.
static func preview_box(on: bool) -> Control:
	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(544, 306)
	frame.add_theme_stylebox_override("panel", UzTheme.box(Color(0, 0, 0, 1), UzTheme.r_panel() - 6, 1, UzTheme.col("stroke")))
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not on:
		var cc := CenterContainer.new()
		U.full_rect(cc)
		cc.add_child(U.label("Kurz auf Schwarz.", "m", "faint", "medium"))
		frame.add_child(cc)
		return frame
	var p: Control = (load("res://src/ui/power_off.gd") as GDScript).new()
	p.set("preview", true)
	frame.add_child(p)
	return frame


# --- Ablauf ------------------------------------------------------------------------------------

func _ready() -> void:
	U.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE if preview else Control.MOUSE_FILTER_STOP
	_screen = ColorRect.new()
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.color = Color.WHITE
	U.full_rect(_screen)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_screen.material = _mat
	add_child(_screen)
	if not preview:
		# Harte Grenze nach der Uhr (_process), dazu ein Zeitgeber, falls _process nicht mehr liefe.
		_start_ms = Time.get_ticks_msec()
		get_tree().create_timer(CAP + 0.25, true).timeout.connect(_finish)
	_apply()


## Klang und Uhr beginnen gemeinsam, sobald das erste Bild gezeichnet ist.
func _start_clock() -> void:
	_t0_us = Time.get_ticks_usec()
	Sfx.last_player = null
	Sfx.play("power_off")
	var p := Sfx.last_player
	if is_instance_valid(p) and p.playing:
		_player = p
		_vol0 = p.volume_db


func _process(dt: float) -> void:
	if preview:
		_t += dt
		if _t > LENGTH + 0.9:
			_t = 0.0
		_apply()
		return
	if _done or _frozen:
		return
	if _t0_us < 0:
		_start_clock()
	else:
		_t = (Time.get_ticks_usec() - _t0_us) / 1000000.0
		_mess.bild(_t)
	var visual := SHORT if mode == "kurz" else LENGTH
	if _skip_at >= 0.0:
		var k := clampf((_t - _skip_at) / SKIP_FADE, 0.0, 1.0)
		if is_instance_valid(_player):
			_player.volume_db = lerpf(_vol0, -60.0, k)
		if k >= 1.0:
			_finish()
	elif _t >= CAP or (_t >= visual and not (is_instance_valid(_player) and _player.playing)):
		_finish()
	elif Time.get_ticks_msec() - _start_ms >= int(CAP * 1000.0):
		# Echtzeit-Grenze, das Bild ist aber noch nicht durch (langsamer PC): nicht schneiden,
		# sondern wie beim Abkürzen in SKIP_FADE (≈ T_WEG) zu Ende ins Schwarz.
		skip()
	_apply()


func _input(e: InputEvent) -> void:
	if preview:
		return
	# Während des Ausschaltens reagiert die Oberfläche dahinter auf nichts mehr.
	if e is InputEventKey or e is InputEventJoypadButton or e is InputEventMouseButton or e is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
	if not _done and _skip_at < 0.0 and _t >= SKIP_GUARD and is_skip(e):
		skip()


## Abkürzen: schnell schwarz, der Klang blendet aus.
func skip() -> void:
	if _done or _skip_at >= 0.0:
		return
	_skip_at = _t
	_skip_black = _black()


## Für Proben: einen festen Zeitpunkt zeigen (läuft dann nicht mehr von selbst weiter).
func seek(t: float) -> void:
	set_process(false)
	_frozen = true
	_done = false
	_t = t
	_apply()


func _finish() -> void:
	if _done or _frozen:
		return
	_done = true
	_t = maxf(_t, LENGTH)
	if is_instance_valid(_player):
		_player.stop()
		_player.volume_db = _vol0
	_apply()
	if _t0_us >= 0:
		_mess.melden("Ausschalten")
	finished.emit()


## Nach dem Ruhezustand (oder wenn Windows das Ausschalten nicht ausführt): wieder aufblenden.
func reveal() -> void:
	if not is_inside_tree():
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(false)
	# Der Shader schreibt seine Deckkraft selbst (modulate erreicht ihn nicht): sie geht mit.
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "modulate:a", 0.0, REVEAL_S)
	if _mat:
		tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("fade", v), 1.0, 0.0, REVEAL_S)
	await tw.finished
	var holder := get_parent()
	if holder is CanvasLayer:
		holder.queue_free()
	else:
		queue_free()


# --- Hilfen ------------------------------------------------------------------------------------

static func _ease_io(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


static func _ease_in(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x


static func _span(t: float, r: Vector2) -> float:
	return clampf((t - r.x) / (r.y - r.x), 0.0, 1.0)


## Der Raum hinter dem Bild wie beim Start (boot.gd), er wird dann ganz schwarz.
static func _room() -> Color:
	return UzTheme.col("bg") if UzTheme.light else UzTheme.col("bg").darkened(0.6)


## Deckkraft des Schwarz über allem (am Ende, beim Abkürzen schneller).
func _black() -> float:
	var b := _ease_io(_span(_t, BLACK_AT)) if mode == "voll" else _ease_io((_t - SHORT + 0.12) / 0.12)
	if _done:
		b = 1.0
	if _skip_at >= 0.0:
		b = maxf(b, lerpf(_skip_black, 1.0, _ease_io((_t - _skip_at) / SKIP_FADE)))
	return b


## Der Zustand des Bilds zum Zeitpunkt t (Werte des Shaders; Maße in Einheiten von 1080 Zeilen,
## u = 1). Reine Rechnung (tests/logic_system.gd).
static func zustand(t: float, m: String) -> Dictionary:
	var dot_r := PUNKT_R
	if m == "kurz":
		# Ohne Bewegung: das Bild blendet ab, der Punkt leuchtet kurz in der Mitte und geht aus.
		var aus := _ease_io(t / 0.35)
		return { "zoom": 1.0, "sx": 1.0, "sy": 1.0, "dicke": 0.0, "ecke": 0.0, "dunkel": aus, "phosphor": 0.0,
			"punkt": 0.0, "schein": 0.0, "form_a": 1.0 - aus,
			"ruhe_punkt": _ease_io((t - 0.12) / 0.18) * (1.0 - _ease_io((t - 0.36) / 0.16)), "punkt_r": dot_r }
	var rec := _ease_io(t / RECEDE)
	var sq := _ease_in(_span(t, SQUASH))
	var sh := _ease_in(_span(t, SHRINK))
	var td := _ease_io(_span(t, TO_DOT))
	var go := _ease_io(_span(t, GLOW_OUT))
	var linie := 2.0
	return {
		"zoom": lerpf(1.0, 0.94, _ease_out(t / RECEDE)),
		"sx": lerpf(1.0 + 0.03 * sq, 0.0, sh),
		"sy": 1.0 - sq,
		"dicke": lerpf(linie * sq, dot_r, td) * (1.0 - 0.35 * go),
		"ecke": 30.0 * rec,
		"dunkel": 0.35 * rec,
		# Hell wie Leuchtstoff erst, während das Bild flach wird: Fläche mal Helligkeit bleibt klein
		# (kein heller Blitz über den ganzen Schirm, keine Helligkeitssprünge).
		"phosphor": pow(sq, 0.6),
		"punkt": td,
		# Licht: wächst mit dem Zusammenfallen, am hellsten als Linie, dann der ruhige Schein der LED.
		"schein": 0.9 * sq * (1.0 - 0.55 * td) * (1.0 - go),
		"form_a": 1.0 - go,
		"ruhe_punkt": 0.0, "punkt_r": dot_r,
	}


# --- Zeichnen ----------------------------------------------------------------------------------

func _apply() -> void:
	var s := size if size.x > 10 else get_viewport_rect().size
	var u := s.y / 1080.0
	if _mat == null:
		return
	var z := zustand(_t, mode)
	for key in z:
		var v: float = z[key]
		if key in ["dicke", "ecke", "punkt_r"]:
			v *= u
		_mat.set_shader_parameter(key, v)
	var xf := get_viewport().get_final_transform() * get_global_transform_with_canvas()
	_mat.set_shader_parameter("groesse", s)
	_mat.set_shader_parameter("px_e", 1.0 / maxf(absf(xf.get_scale().y), 0.01))
	_mat.set_shader_parameter("u", u)
	_mat.set_shader_parameter("raum", _room().lerp(Color.BLACK, _ease_io(_t / 0.6)))
	_mat.set_shader_parameter("akzent", UzTheme.col("accent"))
	_mat.set_shader_parameter("vorschau", 1.0 if preview else 0.0)
	_mat.set_shader_parameter("schwarz", _black())

extends Control
## Die Bühne – der Kopf der Medien-Apps (Videos, Filme, Streams), eine Form für alle
## (docs/PLAN_MEDIEN.md): Das große Bild liegt oben rechts im Raum (movie_backdrop.gd im
## Hintergrund von Uzai, scharf, nach links und unten auslaufend; sein Lichtschein tönt den Raum),
## unten links der Text: ein echter Grund im Akzent, der Titel bzw. Schriftzug, eine leise Zeile,
## darunter als Pillen, was A und X bzw. Y auf der gewählten Karte tun – kein eigener Halt, der
## Cursor bleibt auf der Karte (wie auf der Startseite der Spiele).
##
## Die Bühne zeigt immer, worauf man steht (zeige). Beim Blättern gleitet der Text aus der Richtung
## des Wechsels herein (W_BEREICH in T_RAUM, Zeile für Zeile gestaffelt), das Bild blendet über, sobald es fertig ist (dekodiert im
## Hintergrund-Thread); das scharfe Bild lädt erst, wenn die Auswahl kurz ruht, Nachbarn werden
## vorgeladen (warm). Es stehen nie mehr als zwei Texte
## da (der neue und der eine, der gerade geht).
##
## text: { grund: [Text, Symbol] oder [], titel, logo (Adresse oder ""), zeile, zeile2 (leise,
##   höchstens zwei Zeilen – Beschreibung eines Films), tasten: [[Taste, Wort], …] (höchstens zwei) }
## bild: { key, urls: [groß zuerst], ph: Texture2D (Farbfeld, auch das Licht im Raum),
##   warm: Nachbarn zum Vorladen [Adresse oder [Adressen, groß zuerst]] }

const U := preload("res://src/ui/u.gd")
const Art := preload("res://src/ui/components/movie_art.gd")
const MovieBackdrop := preload("res://src/ui/components/movie_backdrop.gd")

## Height of the stage; the rows start below it. 350 instead of 400 to avoid too much empty space: the first
## row moves up, and the next one is already visible below it.
const H := 350.0
const TEXT_W := 900.0
const LOGO := Vector2(440, 130)
## So lange ruht die Auswahl, bevor das große Bild geladen wird (schnelles Blättern lädt nichts).
const DWELL := 0.14

var section: Control              ## der Bereich, dem die Bühne gehört (sichtbar? gewählt?)
const Main := preload("res://src/main.gd")
var main: Main
var item: Dictionary = {}
var _text: Control
var _sig := ""
var _gen := 0
var _bd = null                    ## movie_backdrop.gd im Hintergrund von Uzai
var _bild: Dictionary = {}
var _bild_key := ""
var _timer: Timer


func setup(sec: Control, m: Main) -> Control:
	section = sec
	main = m
	return self


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(UzTheme.GUTTER, 0)
	size = Vector2(TEXT_W, H - 30.0)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = DWELL
	_timer.timeout.connect(_load_big)
	add_child(_timer)


# --- Zeigen --------------------------------------------------------------------------------------

## it: der Eintrag (Video, Film, Stream); dir: −1/1 aus welcher Richtung geblättert wurde, 0 nur
## blenden; text und bild siehe oben. refresh: derselbe Eintrag neu beschriftet (z. B. nach „Merken“).
func zeige(it: Dictionary, dir: int, text: Dictionary, bild: Dictionary = {}) -> void:
	var sig := _signature(it, text)
	var same := str(it.get("id", "")) == str(item.get("id", "")) and not item.is_empty()
	item = it
	if sig != _sig:
		_sig = sig
		_swap_text(text, 0 if same else dir)
	if not bild.is_empty():
		_show_bild(bild)


## Was der Text zeigt – ändert es sich, wird neu beschriftet (Tasten nur nach ihren Worten, nicht
## nach den Rückrufen: die wären jedes Mal neu).
func _signature(it: Dictionary, text: Dictionary) -> String:
	var worte := PackedStringArray()
	for t in (text.get("tasten", []) if text.get("tasten") is Array else []):
		if t is Array and t.size() >= 2:
			worte.append("%s:%s" % [str(t[0]), str(t[1])])
	return "%s|%s|%s|%s|%s|%s" % [str(it.get("id", "")), str(text.get("grund", [])), str(text.get("titel", "")), str(text.get("zeile", "")),
		str(text.get("zeile2", "")), ",".join(worte)]


## Die Pillen zu einer Karte, aus denselben Hinweisen wie die Tastenzeile unten: A, dann X (wenn
## die Karte auf X reagiert), sonst Y. Mit der Maus: A löst die Karte aus, X bzw. Y ihren Rückruf.
static func tasten_von(card: Control) -> Array:
	if card == null or not is_instance_valid(card):
		return []
	var out: Array = []
	var a := str(card.get_meta("uz_hint_a", ""))
	if a != "" and a != "—":
		out.append(["a", a, func() -> void:
			if is_instance_valid(card):
				Nav.activate(card)])
	for k in ["x", "y"]:
		if card.has_meta("uz_on_" + k) and str(card.get_meta("uz_hint_" + k, "")) != "":
			var cb: Variant = card.get_meta("uz_on_" + k)
			out.append([k, str(card.get_meta("uz_hint_" + k)), cb if cb is Callable else Callable()])
			break
	return out


func _swap_text(text: Dictionary, dir: int) -> void:
	_gen += 1
	var old := _text
	# Was noch vom vorletzten Wechsel ausblendet, sofort entfernen: nie mehr als zwei Texte.
	for ch in get_children():
		if ch != old and ch is Control and ch != _timer:
			_drop(ch)
	_text = _build(text)
	add_child(_text)
	if is_instance_valid(old):
		U.stop(old, "uz_slide")
		var to := U.kreuzen(old, "uz_buehne").set_parallel(true)
		U.kreuz_aus(to, old)
		if dir != 0:
			to.tween_property(old, "offset_left", old.offset_left - dir * U.weg_px(U.W_ORT), U.T_WEG).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			to.tween_property(old, "offset_right", old.offset_right - dir * U.weg_px(U.W_ORT), U.T_WEG).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		to.chain().tween_callback(_drop.bind(old))
		# Sicherheitsnetz, falls die Ausblendung nie endet (abgebrochener Tween): kurz danach weg.
		get_tree().create_timer(U.T_WEG + 0.3).timeout.connect(_drop.bind(old))
	_text.modulate.a = 0.0
	U.ankommen(_text, U.T_ORT, "uz_buehne").tween_property(_text, "modulate:a", 1.0, U.T_ORT).set_delay(U.NACH_WEG)
	# Beim Zappen gleitet der neue Text weiter herein und braucht länger (Raum statt Ort): der
	# Wechsel soll sich anfühlen, nicht nur passieren. Die Zeilen kommen nacheinander – Grund,
	# Titel, Zeile, Pillen.
	if dir != 0:
		U.slide_x(_text, dir * U.weg_px(U.W_BEREICH), U.T_RAUM)
	var col := _text.get_child(0) if _text.get_child_count() > 0 else null
	if col:
		var i := 0
		for z in col.get_children():
			if not (z is Control) or not (z as Control).visible:
				continue
			var ziel := (z as Control).modulate.a
			(z as Control).modulate.a = 0.0
			U.ankommen(z, U.T_RAUM, "uz_zeile").tween_property(z, "modulate:a", ziel, U.T_RAUM).set_delay(U.NACH_WEG + U.staffel(i))
			i += 1


func _drop(v: Variant) -> void:
	if not is_instance_valid(v) or v == _text or v == _timer:
		return
	var c := v as Control
	U.stop(c, "uz_buehne")
	U.stop(c, "uz_slide")
	if c.get_parent() == self:
		remove_child(c)
	c.queue_free()


## Schatten unter der Schrift nur auf dunklem Grund (im hellen Farbschema wäre er ein Doppelstrich).
static func _shadow(l: Label, strength: float) -> Label:
	if not UzTheme.light:
		U.shadow(l, strength)
	return l


func _build(text: Dictionary) -> Control:
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(host)
	var col := U.vbox(12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_END
	col.anchor_bottom = 1.0
	col.offset_right = TEXT_W
	host.add_child(col)
	var grund: Array = text.get("grund", []) if text.get("grund") is Array else []
	if grund.size() >= 1 and str(grund[0]) != "":
		var rr := U.hbox(10)
		rr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if grund.size() >= 2 and str(grund[1]) != "":
			var ic := U.icon(str(grund[1]), 22, "accent")
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			rr.add_child(ic)
		var rl := U.label(str(grund[0]), "s", "accent", "medium")
		rl.clip_text = false
		rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rr.add_child(_shadow(rl, 0.4))
		col.add_child(rr)
	var titel := str(text.get("titel", ""))
	var logo_url := str(text.get("logo", ""))
	var tl := U.label(titel, "xxl", "text", "title", true)
	tl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Titel bleiben, wie der Dienst sie schreibt
	tl.custom_minimum_size = Vector2(TEXT_W, 0)
	tl.max_lines_visible = 2
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.add_theme_constant_override("line_spacing", -6)
	_fit_title(tl)
	_shadow(tl, 0.5)
	# Steht der Titel in zwei Zeilen, bleibt der Beschreibung eine: sonst reicht die Höhe der Bühne nicht.
	tl.size = Vector2(TEXT_W, 0)
	var titel_zeilen := 2 if logo_url == "" and titel != "" and tl.get_line_count() > 1 else 1
	if logo_url != "":
		# Platz für den Schriftzug von Anfang an, damit beim Laden nichts springt.
		var logo := TextureRect.new()
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		logo.custom_minimum_size = LOGO
		logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(logo)
		tl.visible = false
		col.add_child(tl)
		var wl: WeakRef = weakref(logo)
		var wt: WeakRef = weakref(tl)
		var gen := _gen
		Art.load_image(logo_url, int(LOGO.x), func(t: Texture2D) -> void:
			var l: TextureRect = wl.get_ref()
			var ti: Label = wt.get_ref()
			if l == null or ti == null or gen != _gen:
				return
			if t:
				l.texture = t
			else:
				l.visible = false
				ti.visible = true
		)
	else:
		tl.visible = titel != ""
		col.add_child(tl)
	var zeile := str(text.get("zeile", ""))
	if zeile != "":
		var zl := U.label(zeile, "m", "muted", "medium")
		zl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		zl.clip_text = true
		zl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		zl.custom_minimum_size = Vector2(TEXT_W, 0)
		col.add_child(_shadow(zl, 0.4))
	var zeile2 := str(text.get("zeile2", "")).strip_edges()
	if zeile2 != "":
		var d := Art.fit_lines(U.label(zeile2, "m", "text", "regular", true), TEXT_W, 1 if titel_zeilen > 1 else 2)
		d.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		d.modulate.a = 0.86
		col.add_child(_shadow(d, 0.45))
	var tasten: Array = text.get("tasten", []) if text.get("tasten") is Array else []
	if not tasten.is_empty():
		var tm := U.margin(0, 8, 0, 0)
		tm.name = "Tasten"
		tm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := U.hbox(12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tm.add_child(row)
		for i in mini(tasten.size(), 2):
			var t: Array = tasten[i]
			if t.size() < 2 or str(t[1]) == "":
				continue
			var k := _Taste.new()
			k.cmd = str(t[0])
			k.primary = i == 0
			k.on_press = t[2] if t.size() >= 3 and t[2] is Callable else Callable()
			k.set_text(str(t[1]))
			row.add_child(k)
		col.add_child(tm)
	return host


## Ein- oder zweizeilig, je nach Länge: feste Höhe, damit „…“ bei zu langen Titeln greift (ein
## umbrechendes Label mit Kürzung meldet sonst nur 1 Pixel Höhe).
static func _fit_title(l: Label) -> void:
	var f := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	var lh := f.get_height(fs)
	var full := f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, TEXT_W, fs)
	var lines := clampi(roundi(full.y / lh), 1, 2)
	l.custom_minimum_size = Vector2(TEXT_W, lh * lines + float(l.get_theme_constant("line_spacing")) * (lines - 1))


# --- Bild ----------------------------------------------------------------------------------------

## Das Bild oben rechts und das Licht im Raum zu einem Eintrag (siehe Kopf: bild).
func _show_bild(b: Dictionary) -> void:
	var key := str(b.get("key", ""))
	if key == _bild_key or key == "":
		return
	_bild_key = key
	_bild = b
	if not _paint_ok():
		return
	_ensure_bd()
	var urls: Array = b.get("urls", []) if b.get("urls") is Array else []
	var ph: Texture2D = b.get("ph") if b.get("ph") is Texture2D else null
	# Das Bild im Raum: schon geladen kommt es sofort, sonst nach einer kurzen Ruhe.
	_bd.show_item({ "id": key, "background": str(urls[0]) if not urls.is_empty() else "", "_urls": urls, "_ph": ph }, _bd.item.is_empty())
	_timer.start()
	# Ambient light: only the color swatch, never a blurred copy of the same image. Two versions of one
	# image cross-fading at different times looked like a ghost image.
	main.background.show_blurred(ph, "mb:" + key)


## Die Auswahl ruht: die großen Bilder der Nachbarn (bild.warm) vorladen – in genau der Größe,
## in der movie_backdrop sie zeigt (sonst lüde es sie beim Weiterblättern noch einmal). Beim
## Weiterblättern steht das Bild dann sofort, statt erst nach dem Laden überzublenden. Das eigene
## große Bild holt movie_backdrop nach seiner Ruhe selbst. Je Nachbar eine Adresse oder eine Liste.
func _load_big() -> void:
	if not _paint_ok() or not is_instance_valid(_bd):
		return
	var warm: Array = _bild.get("warm", []) if _bild.get("warm") is Array else []
	_bd.vorladen(warm.slice(0, 4))


## Darf die Bühne den Raum bemalen? Nur, wenn ihr Bereich zu sehen und gewählt ist (unsichtbar
## vorgebaut: nie – das Bild läge sonst über der Startseite).
func _paint_ok() -> bool:
	if main == null or not is_instance_valid(main.background) or section == null or not is_instance_valid(section):
		return false
	return section.visible and is_visible_in_tree() and str(main.current) == str(section.get("id"))


func _ensure_bd() -> void:
	if is_instance_valid(_bd):
		U.stop(_bd, "uz_bdv")
		if _bd.modulate.a < 1.0:
			U.ankommen(_bd, U.T_ORT, "uz_bdv").tween_property(_bd, "modulate:a", 1.0, U.T_ORT)
		return
	_bd = MovieBackdrop.new()
	_bd.layout = "hero"
	_bd.name = "MedienBild"
	main.background.add_child(_bd)


## Beim Betreten (on_enter, reenter): Bild und Licht zum gezeigten Eintrag wieder herstellen –
## main.goto hat den Raum geleert.
func wieder() -> void:
	if _bild.is_empty():
		return
	var b := _bild
	_bild_key = ""
	_show_bild(b)


## Beim Verlassen des Bereichs: das Bild geht weich (das Licht im Raum nimmt sich main.goto).
func verlassen() -> void:
	if not is_instance_valid(_bd):
		_bd = null
		return
	var bd: Control = _bd
	_bd = null
	var tw := U.weg(bd, "uz_bdv")
	tw.tween_property(bd, "modulate:a", 0.0, U.T_WEG)
	tw.tween_callback(bd.queue_free)


func _exit_tree() -> void:
	if is_instance_valid(_bd):
		_bd.queue_free()
		_bd = null


# --- Pille mit Taste -----------------------------------------------------------------------------

## Pille im Kopf: hell die Haupthandlung (A), leise die zweite (X oder Y) – echte Fläche wie der
## ruhige Knopf (U.knopf_farben), vorn die Taste, dann das Wort. Kein Halt für den Controller (der
## Cursor bleibt auf der Karte, ein Druck genügt); mit der Maus klickbar.
class _Taste extends Control:
	const UU := preload("res://src/ui/u.gd")
	const HH := 52.0
	const PAD_R := 24.0
	var primary := false
	var cmd := "a"
	var on_press: Callable
	var _text := ""

	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		Nav.device_changed.connect(func(_k: String) -> void: set_text(_text, true))
		if _text != "":
			set_text(_text, true)

	func set_text(t: String, neu := false) -> void:
		if t == _text and custom_minimum_size.x > 0.0 and not neu:
			return
		_text = t
		var w := UzTheme.font("ui_bold").get_string_size(tr(t), HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("m")).x
		# Nur das Wort, wie alle Knöpfe seit dem Premium-Durchgang; die Taste steht in der Tastenzeile.
		custom_minimum_size = Vector2(ceilf(PAD_R * 2.0 + w), HH)
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var f := UU.knopf_farben("primary" if primary else "")
		# Dieselbe Fläche wie der ruhige Knopf (U.ruhig): deckend, Lichtkante oben, die Haupthandlung
		# ruht gehoben (UU.KNOPF_RUHT) – keine Kontur rundherum.
		var sb := UzTheme.flaeche(f.rest as Color, 999)
		var ruht := float(f.get("schatten", 0.0))
		if ruht > 0.0:
			sb.shadow_color = Color(0, 0, 0, UzTheme.shadow_alpha(UU.KNOPF_RUHT.x * ruht))
			sb.shadow_size = int(round(UU.KNOPF_RUHT.y * ruht))
			sb.shadow_offset = Vector2(0, 4)
		draw_style_box(sb, r)
		var fnt := UzTheme.font("ui_bold")
		var fs := UzTheme.size("m")
		var y := (size.y - fnt.get_height(fs)) * 0.5 + fnt.get_ascent(fs)
		draw_string(fnt, Vector2(PAD_R, y), tr(_text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, f.ink as Color)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if on_press.is_valid():
				on_press.call()

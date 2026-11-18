extends Control
## Eine Einstellung. Arten:
##  toggle  – an/aus (A oder links/rechts)
##  choice  – Auswahl aus Liste (links/rechts blättert, A nächste)
##  slider  – Zahl in Schritten (links/rechts), mit Schiene
##  action  – Knopf, der etwas öffnet oder ausführt (A)
##  info    – nur Anzeige: kein Pfeil, A tut nichts
## Für Pfad, Text und Farbe ist es "action" mit eigenem Wert-Text und einer Funktion.
##
## nur_a (Einstellungen, settings_bausteine.gd): Werte ändert nur A, das Steuerkreuz bleibt
## Bewegung zwischen den Spalten – links zurück (Kategorien, aus einer Unterseite hinaus), rechts
## hinein. A kippt den Schalter, wechselt eine Auswahl mit zwei Werten, öffnet bei mehr die
## Auswahlliste; beim Regler beginnt A das Einstellen (dann links/rechts), A oder B beendet es.
##
## Bewegung: Der Schalter gleitet (und dehnt sich dabei kurz), die Schiene füllt sich weich, ein
## gewechselter Wert schiebt sich aus der Richtung des Drucks herein. Wird die Zeile neu gebaut
## (etwa weil das Farbschema alles neu zeichnet), läuft die Bewegung vom alten Wert aus weiter.
## Lange Werte (Pfade) werden gekürzt statt in die Nachbarspalte zu laufen.

signal changed(value: Variant)
signal focused_row

const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")

var kind := "action"
var title := ""
var desc := ""
var value: Variant = null
var options: Array = []          # [[wert, "Text"], ...] für choice
var min_v := 0.0
var max_v := 1.0
var step := 0.1
var fmt := "%d %%"
var fmt_scale := 100.0
var value_raw := false           ## der Wert rechts (action/info) ist ein Name oder eigener Text: nie übersetzen
var value_text := "":            # für action/info: angezeigter Wert
	set(v):
		value_text = v
		if _ready_done:
			_layout_value()
var swatch := Color.TRANSPARENT:  # für Farben
	set(v):
		swatch = v
		if _ready_done:
			_layout_value()
var on_activate: Callable
var icon_name := "":
	set(v):
		icon_name = v
		if _icon_r:
			_icon_r.texture = Icons.tex(v, 24) if v != "" else null
			_icon_r.visible = v != ""
# Alles Folgende ist freiwillig – und darf auch noch nach dem Einhängen gesetzt werden.
var subtitle := "":               ## zweite, leise Zeile unter dem Titel
	set(v):
		subtitle = v
		if _sub_l:
			_sub_l.text = v
			_sub_l.visible = v != ""
			_fit_height()
var compact := false              ## Einstellungen: 64 px statt 72 px hoch, mehr Zeilen auf einen Blick
var dot := Color.TRANSPARENT:     ## farbiger Punkt vor dem Titel (z. B. die Farbe eines Systems)
	set(v):
		dot = v
		if _dot_c:
			_dot_c.visible = v.a > 0.0
			_dot_c.queue_redraw()
var tone := "":                   ## Farbe des Werts: "" leise, "ok", "warn", "faint", "text", "accent"
	set(v):
		tone = v
		queue_redraw()
var track_colors := PackedColorArray()   ## Schiene als Farbverlauf (Farbwahl)
var track_dim := false:           ## Schiene leise statt in der Akzentfarbe (stumm im Mixer)
	set(v):
		track_dim = v
		queue_redraw()
var focus_radius := -1            ## Rundung der hellen Auswahl (in Gruppenkarten etwas kleiner)
var value_max_w := 460.0          ## breiter wird ein Wert nie
var nur_a := false                ## Werte nur mit A (Einstellungen): links/rechts bleibt Bewegung

const SW_SIZE := Vector2(60, 34)
const STELL_NEU_MS := 4000          ## so lange nach dem letzten Schritt stellt eine neu gebaute Zeile weiter ein
const SW_ECKIG := Vector2(38, 22)    ## Schalter der Listen-Sprache (Pille, wie im Guide: Liste.schalter)
const TRACK_W := 196.0
const TRACK_MIN := 110.0            ## kürzer wird die Schiene nie (wenig Platz: Titel bricht nicht im Wort)
const CHEV := 20.0

static var _mem := {}            ## uz_key → { v: zuletzt gezeigter Zustand, t: Zeitpunkt } (Bewegung nach Neuaufbau)
## Regler, der gerade eingestellt wird (uz_key, Zeitpunkt): Baut sich die Oberfläche dabei neu (Größe
## der Oberfläche), stellt die neue Zeile mit dem Cursor gleich weiter ein.
static var _stell_key := ""
static var _stell_ms := 0
static var _tnum_font: FontVariation
static var _tnum_base: Font

var _va: Control                 # Platz für Wert, Schiene oder Schalter (wird selbst gezeichnet)
var _m: MarginContainer
var _icon_r: TextureRect
var _dot_c: Control
var _title_l: Label
var _sub_l: Label
var _shown := ""                 # gezeigter Wert-Text (gekürzt)
var _prev_shown := ""
var _slide := 1.0                # 0 → 1: neuer Wert schiebt sich herein
var _slide_dir := 1
var _knob := 0.0                 # Schalter 0 (aus) … 1 (an)
var _fill := 0.0                 # Schiene 0 … 1
var _nudge := 0.0                # Pfeil in Druckrichtung kurz anstoßen
var _stellen := false            # Regler (nur_a): A hat das Einstellen begonnen, links/rechts ändert
var _stell := 0.0                # 0 → 1: Griff hebt sich beim Einstellen
var _track_w := TRACK_W          # Länge der Schiene (kürzer, wenn der Titel sonst im Wort bräche)
var _hint_vorher := ""           # Hinweis für A vor dem Einstellen
var _ready_done := false


func setup(k: String, t: String, d := "", v: Variant = null) -> Control:
	kind = k
	title = t
	desc = d
	value = v
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Wer die Zeile baut, darf den Hinweis vorgeben („Anwenden“, „Aufs Handy“).
	if not has_meta("uz_hint_a"):
		set_meta("uz_hint_a", _hint())
	_m = U.margin(20, 8, 22, 8) if compact else U.margin(20, 12, 22, 12)
	U.full_rect(_m)
	add_child(_m)
	var row := U.hbox(18)
	_m.add_child(row)
	_icon_r = U.icon(icon_name if icon_name != "" else "info", 24, "muted")
	_icon_r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon_r.visible = icon_name != ""
	row.add_child(_icon_r)
	_dot_c = Control.new()
	_dot_c.custom_minimum_size = Vector2(14, 14)
	_dot_c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dot_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot_c.visible = dot.a > 0.0
	_dot_c.draw.connect(_draw_dot)
	row.add_child(_dot_c)
	var col := U.vbox(1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	# Passt der Titel nicht in eine Zeile (große Oberfläche, lange Übersetzung), bricht er auf
	# höchstens zwei um, statt mitten im Wort mit „…“ zu enden; die Zeile wächst dann mit.
	_title_l = U.label(title, "m", "text", "ui")
	_title_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_l.max_lines_visible = 2
	_title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_title_l)
	_sub_l = U.ellipsis(U.label(subtitle, "s", "muted", "regular"))
	_sub_l.visible = subtitle != ""
	col.add_child(_sub_l)
	row.add_child(col)
	_va = Control.new()
	_va.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_va.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Wert, Schiene und Schalter zeichnet die Zeile selbst: neu zeichnen, sobald der Platz sitzt.
	_va.item_rect_changed.connect(queue_redraw)
	row.add_child(_va)
	_init_state()
	_refresh()
	_fit_height()
	_m.minimum_size_changed.connect(_fit_height)
	resized.connect(_layout_value)
	focus_entered.connect(func() -> void:
		Liste.fokus(self, true)
		queue_redraw()
		focused_row.emit()
		if _stell_key != "" and _stell_key == _key() and Time.get_ticks_msec() - _stell_ms < STELL_NEU_MS:
			_stellen_setzen(true, false)
		elif _stell_key != _key():
			_stell_key = ""
	)
	focus_exited.connect(func() -> void:
		Liste.fokus(self, false)
		_stellen_setzen(false, false)
		queue_redraw()
	)
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)
	_ready_done = true
	_remember()


func _fit_height() -> void:
	if _m:
		var h := (64.0 if subtitle == "" else 76.0) if compact else (72.0 if subtitle == "" else 82.0)
		custom_minimum_size.y = maxf(h, _m.get_combined_minimum_size().y)


func _draw_dot() -> void:
	var c := _dot_c.size * 0.5
	if UzTheme.strict():
		_dot_c.draw_circle(c, 6.0, dot, true, -1.0, true)
		return
	_dot_c.draw_circle(c + Vector2(0, 1), 8.0, Color(0, 0, 0, 0.3), true, -1.0, true)
	_dot_c.draw_circle(c, 7.0, dot, true, -1.0, true)


func _hint() -> String:
	match kind:
		"toggle": return "Umschalten"
		"choice": return "Auswählen" if nur_a and options.size() > 2 else "Wechseln"
		"slider": return "Einstellen" if nur_a else "Ändern"
		"info": return "—"
	return "Öffnen"


func _key() -> String:
	return str(get_meta("uz_key", "")) if has_meta("uz_key") else ""


## Anfangszustand; nach einem Neuaufbau läuft die Bewegung vom zuletzt gezeigten Zustand aus.
func _init_state() -> void:
	var k := _key()
	var old: Variant = null
	# Nur ein Neuaufbau gleich danach zählt – nicht dieselbe Zeile in einem anderen Menü später.
	if k != "" and _mem.has(k) and Time.get_ticks_msec() - int(_mem[k].t) < 600:
		old = _mem[k].v
	match kind:
		"toggle":
			var to := 1.0 if bool(value) else 0.0
			_knob = to
			if old is float and not is_equal_approx(float(old), to):
				_knob = float(old)
				_animate_knob.call_deferred(to)
		"slider":
			var to2 := _norm()
			_fill = to2
			if old is float and not is_equal_approx(float(old), to2):
				_fill = float(old)
				_animate_fill.call_deferred(to2)
		"choice":
			if old is Array and (old as Array).size() == 2 and str(old[0]) != _option_text():
				_prev_shown = str(old[0])
				_slide = 0.0
				_slide_dir = int(old[1])
				_animate_slide.call_deferred(_slide_dir)


## Merkt sich, was gerade zu sehen ist (nicht das Ziel): Eine neu gebaute Zeile setzt dort an.
func _remember() -> void:
	var k := _key()
	if k == "":
		return
	var v: Variant = null
	match kind:
		"toggle": v = _knob
		"slider": v = _fill
		"choice": v = [_prev_shown if (_prev_shown != "" and _slide < 0.5) else _shown, _slide_dir]
	if v != null:
		_mem[k] = { "v": v, "t": Time.get_ticks_msec() }


func _norm() -> float:
	if max_v <= min_v:
		return 0.0
	return clampf((float(value if value != null else min_v) - min_v) / (max_v - min_v), 0.0, 1.0)


func _refresh() -> void:
	if _ready_done:
		# Den Zustand vor der Änderung frisch merken: Baut sich die Zeile gleich neu auf
		# (Farbschema), setzt die neue genau hier an.
		_remember()
	match kind:
		"toggle":
			if _ready_done:
				_animate_knob(1.0 if bool(value) else 0.0)
		"slider":
			if _ready_done:
				_animate_fill(_norm())
	_layout_value()
	queue_redraw()


## Text, der rechts steht (ungekürzt).
func _full_text() -> String:
	match kind:
		"choice": return _option_text()
		"slider": return fmt % (float(value if value != null else min_v) * fmt_scale)
		"toggle": return ""
	return value_text


func _option_text() -> String:
	for o in options:
		if o[0] == value:
			return str(o[1])
	return str(value) if value != null else ""


## Breite des Wertbereichs neu bestimmen (und lange Werte kürzen).
func _layout_value() -> void:
	if _va == null:
		return
	var f := _font()
	var fs := UzTheme.size("m")
	# Der Wert bekommt, was der Titel übrig lässt – aber mindestens gut ein Drittel der Zeile. Nie so
	# viel, dass der Titel mitten im Wort umbräche (große Oberfläche, lange Übersetzung): dann wird
	# der Wert gekürzt bzw. die Schiene des Reglers kürzer.
	var maxw := value_max_w
	var frei := INF
	if size.x > 100.0:
		var used := 20.0 + 22.0 + 18.0 + 12.0
		if _icon_r and _icon_r.visible:
			used += 24.0 + 18.0
		if _dot_c and _dot_c.visible:
			used += 14.0 + 18.0
		var tf: Font = _title_l.get_theme_font("font") if _title_l else null
		var tw := tf.get_string_size(tr(title), HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("m")).x if tf else 0.0
		maxw = minf(value_max_w, maxf(size.x - used - tw, size.x * 0.36))
		if tf:
			var wort := 0.0
			for teil in tr(title).split(" ", false):
				wort = maxf(wort, tf.get_string_size(teil, HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("m")).x)
			frei = maxf(size.x - used - ceilf(wort) - 4.0, 0.0)
			maxw = minf(maxw, frei)
	var w := 0.0
	match kind:
		"toggle":
			# Eckig (Marke): „An“/„Aus“ steht leise vor dem Schalter, wie im Guide.
			if UzTheme.strict():
				var aw := maxf(f.get_string_size(tr("Aus"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, f.get_string_size(tr("An"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
				_va.custom_minimum_size = Vector2(ceilf(aw) + 14.0 + SW_ECKIG.x, 34)
			else:
				_va.custom_minimum_size = SW_SIZE
			return
		"slider":
			_shown = _full_text()
			var tw := maxf(f.get_string_size(_wert(_shown), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, 76.0)
			_track_w = clampf(frei - 20.0 - tw, TRACK_MIN, TRACK_W)
			w = _track_w + 20.0 + tw
		"choice":
			# nur_a: ein Pfeil rechts (A wechselt bzw. öffnet die Liste) statt ‹ › – links/rechts
			# ändern hier nichts.
			var pfeile := (CHEV + 12.0) * (1.0 if nur_a else 2.0)
			_shown = fit_text(_full_text(), maxw - pfeile, f, fs)
			w = f.get_string_size(_wert(_shown), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + pfeile
			if _prev_shown != "" and _slide < 1.0:
				w = maxf(w, f.get_string_size(_wert(_prev_shown), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + pfeile)
		"info":
			_shown = fit_text(_full_text(), maxw, f, fs)
			w = f.get_string_size(_wert(_shown), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_:
			_shown = fit_text(_full_text(), maxw - CHEV - 12.0 - (42.0 if swatch.a > 0.0 else 0.0), f, fs)
			w = f.get_string_size(_wert(_shown), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			w += CHEV + (12.0 if _shown != "" else 0.0)
			if swatch.a > 0.0:
				w += 42.0
	_va.custom_minimum_size = Vector2(ceilf(w), 34)
	queue_redraw()


## Text auf eine Breite bringen. Pfade verlieren vorne Ordner („…\Spiele\PS2“), sonst hinten „…“.
static func fit_text(t: String, maxw: float, f: Font, fs: int) -> String:
	if t == "" or f.get_string_size(TranslationServer.translate(t), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= maxw:
		return t
	var sep := "\\" if t.contains("\\") else ("/" if t.contains("/") else "")
	if sep != "":
		var parts := t.split(sep, false)
		for i in range(1, parts.size()):
			var cand := "…" + sep + sep.join(parts.slice(i))
			if f.get_string_size(TranslationServer.translate(cand), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= maxw:
				return cand
		t = parts[parts.size() - 1] if not parts.is_empty() else t
	var out := t
	while out.length() > 1 and f.get_string_size(TranslationServer.translate(out + "…"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > maxw:
		out = out.substr(0, out.length() - 1)
	return out.strip_edges() + "…"


## Schrift für Werte: Bedienschrift mit Ziffern gleicher Breite (nichts wackelt beim Zählen).
static func _font() -> Font:
	var base := UzTheme.ui("ui")
	if _tnum_font == null or _tnum_base != base:
		_tnum_base = base
		_tnum_font = FontVariation.new()
		_tnum_font.base_font = base
		var ts := TextServerManager.get_primary_interface()
		_tnum_font.opentype_features = { ts.name_to_tag("tnum"): 1 }
	return _tnum_font


# --- Bewegung -----------------------------------------------------------------------------

func _set_knob(v: float) -> void:
	_knob = v
	_remember()
	queue_redraw()


func _set_fill(v: float) -> void:
	_fill = v
	_remember()
	queue_redraw()


func _set_slide(v: float) -> void:
	_slide = v
	if v >= 1.0:
		_prev_shown = ""
		_layout_value()
	_remember()
	queue_redraw()


func _set_nudge(v: float) -> void:
	_nudge = v
	queue_redraw()


func _animate_knob(to: float) -> void:
	if not is_inside_tree():
		_knob = to
		return
	U.tw(self, "uz_knob", Tween.TRANS_QUART, Tween.EASE_OUT).tween_method(_set_knob, _knob, to, U.T_ANTWORT)


func _animate_fill(to: float) -> void:
	if not is_inside_tree():
		_fill = to
		return
	U.tw(self, "uz_fill", Tween.TRANS_CUBIC, Tween.EASE_OUT).tween_method(_set_fill, _fill, to, U.T_ANTWORT)


func _animate_slide(dir: int) -> void:
	if not is_inside_tree():
		_slide = 1.0
		return
	_slide_dir = dir
	_slide = 0.0
	_remember()
	U.tw(self, "uz_slide", Tween.TRANS_CUBIC, Tween.EASE_OUT).tween_method(_set_slide, 0.0, 1.0, U.T_ANTWORT)
	var n := U.tw(self, "uz_nudge", Tween.TRANS_SINE, Tween.EASE_OUT)
	n.tween_method(_set_nudge, 0.0, 1.0, U.T_ANTWORT)
	n.tween_method(_set_nudge, 1.0, 0.0, U.T_ORT)


## Klang beim Bestätigen (Nav fragt hier nach): Schalter klingen nach an bzw. aus.
## A gedrückt: nur der Rahmen drückt (Liste.druck), die Zeile wird nicht skaliert.
func press_feedback() -> void:
	Liste.druck(self)


func activate_sound() -> String:
	match kind:
		"toggle": return "toggle_off" if bool(value) else "toggle_on"
		"choice", "slider": return "tick"
		"info": return "bump"
	return "select"


func activate() -> void:
	match kind:
		"toggle":
			value = not bool(value)
			_refresh()
			changed.emit(value)
		"choice":
			if nur_a and options.size() > 2 and _auswahl_oeffnen():
				return
			_step_choice(1)
		"slider":
			if nur_a:
				_stellen_setzen(not _stellen)
				return
			nav_lr(1)
		"action":
			if on_activate.is_valid():
				on_activate.call()


## Auswahl mit mehr als zwei Werten (nur_a): die Auswahlliste wie überall in Uzai. false, wenn es
## keine gibt (ohne Hauptfenster, etwa in Tests): dann wechselt A zum nächsten Wert.
func _auswahl_oeffnen() -> bool:
	var m: Node = get_tree().current_scene if is_inside_tree() else null
	if m == null or not m.has_method("open_choice"):
		return false
	var wr: WeakRef = weakref(self)
	m.call("open_choice", title, options, value, func(v: Variant) -> void:
		var r: Control = wr.get_ref()
		if r == null or v == r.get("value"):
			return
		r.call("_waehlen", v))
	return true


## Wert aus der Auswahlliste: gleitet aus der Richtung herein, in der er in der Liste liegt.
func _waehlen(v: Variant) -> void:
	var alt := -1
	var neu := -1
	for i in options.size():
		if options[i][0] == value:
			alt = i
		if options[i][0] == v:
			neu = i
	_prev_shown = _shown
	value = v
	_refresh()
	_animate_slide(1 if neu >= alt else -1)
	changed.emit(value)


## Regler (nur_a): Einstellen an/aus. Der Griff hebt sich, unten steht „Ändern“ und „Fertig“.
## merken = false: nur diese Zeile (Fokus geht, Neuaufbau), nicht das Ende des Einstellens.
func _stellen_setzen(an: bool, merken := true) -> void:
	if _stellen == an or kind != "slider":
		return
	_stellen = an
	if merken or an:
		_stell_key = _key() if an else ""
		_stell_ms = Time.get_ticks_msec()
	if an:
		_hint_vorher = str(get_meta("uz_hint_a", _hint()))
	set_meta("uz_hint_a", "Fertig" if an else _hint_vorher)
	if an:
		set_meta("uz_hint_lr", "Ändern")
		set_meta("uz_hint_b", "Fertig")
	else:
		remove_meta("uz_hint_lr")
		remove_meta("uz_hint_b")
	if is_inside_tree():
		U.tw(self, "uz_stell", Tween.TRANS_CUBIC, Tween.EASE_OUT).tween_method(func(v: float) -> void:
			_stell = v
			queue_redraw(), _stell, 1.0 if an else 0.0, U.T_ANTWORT)
		if has_focus():
			Nav.focus_moved.emit(self)
	else:
		_stell = 1.0 if an else 0.0


## B beim Einstellen beendet es (Nav fragt hier vor dem Zurück).
func nav_b() -> bool:
	if not _stellen:
		return false
	_stellen_setzen(false)
	Sfx.play("back")
	return true


func nav_lr(dir: int) -> bool:
	if nur_a and not _stellen:
		# Links zurück: aus einer Unterseite hinaus (uz_links_zurueck), sonst sucht Nav die Spalte
		# links (Kategorien). Rechts gibt es neben den Zeilen nichts (uz_lr_block).
		if dir < 0 and has_meta("uz_links_zurueck"):
			var cb: Variant = get_meta("uz_links_zurueck")
			if cb is Callable and (cb as Callable).is_valid():
				(cb as Callable).call()
				return true
		if dir > 0 and has_meta("uz_lr_block"):
			Sfx.play("bump")
			return true
		return false
	match kind:
		"toggle":
			if (dir > 0) != bool(value):
				value = dir > 0
				_refresh()
				changed.emit(value)
				Sfx.play("toggle_on" if dir > 0 else "toggle_off")
			else:
				Sfx.play("bump")
			return true
		"choice":
			_step_choice(dir)
			Sfx.play("tick")
			return true
		"slider":
			if _stellen:
				_stell_ms = Time.get_ticks_msec()
			var nv := clampf(snappedf(float(value if value != null else min_v) + step * dir, step), min_v, max_v)
			if nv != float(value if value != null else min_v):
				value = nv
				_refresh()
				changed.emit(value)
				Sfx.play("tick")
			else:
				Sfx.play("bump")
			return true
	if dir > 0 and has_meta("uz_lr_block"):
		Sfx.play("bump")
		return true
	return false


func _step_choice(dir: int) -> void:
	if options.is_empty():
		return
	var idx := 0
	for i in options.size():
		if options[i][0] == value:
			idx = i
	idx = (idx + dir + options.size()) % options.size()
	_prev_shown = _shown
	value = options[idx][0]
	_refresh()
	_animate_slide(dir)
	changed.emit(value)


func set_value_text(t: String) -> void:
	value_text = t
	_refresh()


# --- Zeichnen -------------------------------------------------------------------------------

func _local_rect(c: Control) -> Rect2:
	var p := Vector2.ZERO
	var n: Node = c
	while n != null and n != self:
		if n is Control:
			p += (n as Control).position
		n = n.get_parent()
	return Rect2(p, c.size)


func _tone_color() -> Color:
	match tone:
		"ok": return UzTheme.col("ok")
		"warn": return UzTheme.col("warn")
		"faint": return UzTheme.col("faint")
		"text": return UzTheme.col("text")
		"accent": return UzTheme.col("accent")
	return UzTheme.col("muted")


func _draw() -> void:
	Liste.zeilen_auswahl(self, focus_radius)
	if _va == null:
		return
	# Auf der hellen Auswahl werden Wert und Zeichen dunkel; im Rahmen-Cursor bleiben sie, wie sie sind.
	var f: float = 0.0 if UzTheme.cursor_frame() else get_meta("uz_f", 1.0 if has_focus() else 0.0)
	var r := _local_rect(_va)
	var dark := UzTheme.col("on_focus")
	match kind:
		"toggle": _draw_switch(r, f, dark)
		"slider": _draw_slider(r, f, dark)
		"choice": _draw_choice(r, f, dark)
		"info": _draw_text_right(_shown, r, _tone_color().lerp(dark, f), 0.0, 1.0)
		_: _draw_action(r, f, dark)


## Der Wert so, wie er dasteht: übersetzt, außer er ist ein Name oder eigener Text (value_raw).
func _wert(t: String) -> String:
	return t if value_raw else tr(t)


func _draw_text_right(t: String, r: Rect2, c: Color, dx: float, alpha: float) -> void:
	if t == "" or alpha <= 0.0:
		return
	var fnt := _font()
	var fs := UzTheme.size("m")
	var w := fnt.get_string_size(_wert(t), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var y := r.position.y + (r.size.y - fnt.get_height(fs)) * 0.5 + fnt.get_ascent(fs)
	draw_string(fnt, Vector2(r.end.x - w + dx, y), _wert(t), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(c, c.a * alpha))


func _chevron(name: String, at: Vector2, c: Color, px := CHEV) -> void:
	draw_texture_rect(Icons.tex(name, int(px)), Rect2(at - Vector2(px, px) * 0.5, Vector2(px, px)), false, c)


func _draw_choice(r: Rect2, f: float, dark: Color) -> void:
	var cy := r.get_center().y
	var chev_c := UzTheme.col("faint").lerp(dark, f)
	var rx := r.end.x - CHEV * 0.5 + (_nudge * 4.0 if _slide_dir > 0 else 0.0)
	_chevron("chevron_right", Vector2(rx, cy), chev_c)
	var inner := Rect2(r.position.x, r.position.y, r.size.x - CHEV - 12.0, r.size.y)
	if not nur_a:
		var lx := r.position.x + CHEV * 0.5 - (_nudge * 4.0 if _slide_dir < 0 else 0.0)
		_chevron("chevron_left", Vector2(lx, cy), chev_c)
		inner = Rect2(r.position.x + CHEV + 12.0, r.position.y, r.size.x - (CHEV + 12.0) * 2.0, r.size.y)
	var c := _tone_color().lerp(dark, f)
	var e := _slide
	if _prev_shown != "" and e < 1.0:
		_draw_text_right(_prev_shown, inner, c, -_slide_dir * 22.0 * e, 1.0 - e)
		_draw_text_right(_shown, inner, c, _slide_dir * 22.0 * (1.0 - e), e)
	else:
		_draw_text_right(_shown, inner, c, 0.0, 1.0)


func _draw_action(r: Rect2, f: float, dark: Color) -> void:
	var cy := r.get_center().y
	_chevron("chevron_right", Vector2(r.end.x - CHEV * 0.5, cy), UzTheme.col("faint").lerp(dark, f), 22.0)
	var tr := Rect2(r.position.x, r.position.y, r.size.x - CHEV - 12.0, r.size.y)
	_draw_text_right(_shown, tr, _tone_color().lerp(dark, f), 0.0, 1.0)
	if swatch.a > 0.0:
		var fnt := _font()
		var tw := fnt.get_string_size(_wert(_shown), HORIZONTAL_ALIGNMENT_LEFT, -1, UzTheme.size("m")).x if _shown != "" else -12.0
		var c := Vector2(tr.end.x - tw - 12.0 - 15.0, cy)
		if UzTheme.strict():
			# Marke: ein weich gerundetes Farbfeld mit Haarlinie.
			var q := Rect2(c - Vector2(13, 13), Vector2(26, 26))
			draw_style_box(UzTheme.box(swatch, 7, 1, UzTheme.col("line")), q)
		else:
			draw_circle(c + Vector2(0, 1.5), 16.5, Color(0, 0, 0, 0.3 * (1.0 - f)), true, -1.0, true)
			draw_circle(c, 15.0, swatch, true, -1.0, true)


func _draw_slider(r: Rect2, f: float, dark: Color) -> void:
	var cy := r.get_center().y
	var x0 := r.position.x + 9.0
	var x1 := r.position.x + _track_w - 9.0
	var fill_x := lerpf(x0, x1, _fill)
	if UzTheme.strict():
		_draw_slider_eckig(r, x0, x1, fill_x, cy, f, dark)
		return
	if not track_colors.is_empty():
		_draw_gradient_track(Rect2(x0 - 6.0, cy - 6.0, (x1 - x0) + 12.0, 12.0))
		var kc := _gradient_at(_fill)
		draw_circle(Vector2(fill_x, cy), 13.0, UzTheme.col("text").lerp(dark, f))
		draw_circle(Vector2(fill_x, cy), 9.5, kc)
	else:
		var base := Color(UzTheme.col("text"), 0.14).lerp(Color(dark, 0.2), f)
		var fill := UzTheme.col("faint" if track_dim else "accent").lerp(dark, f)
		_round_line(x0, x1, cy, 6.0, base)
		if fill_x > x0 + 0.5:
			_round_line(x0, fill_x, cy, 6.0, fill)
		var knob := UzTheme.col("text").lerp(dark, f)
		# Beim Einstellen (nur_a) hebt sich der Griff etwas.
		draw_circle(Vector2(fill_x, cy + 1.5), 11.0 + 3.0 * _stell, Color(0, 0, 0, 0.18 * (1.0 - f)))
		draw_circle(Vector2(fill_x, cy), 10.0 + 3.0 * _stell, knob)
	var tr := Rect2(r.position.x + _track_w + 20.0, r.position.y, r.size.x - _track_w - 20.0, r.size.y)
	_draw_text_right(_shown, tr, _tone_color().lerp(UzTheme.col("text"), _stell).lerp(dark, f), 0.0, 1.0)


## Regler der Listen-Sprache (wie im Guide): dünne Spur, gefüllt im Akzent, eckiger Griff;
## als Farbverlauf ein flaches Band mit eckigem Griff in der gewählten Farbe.
func _draw_slider_eckig(r: Rect2, x0: float, x1: float, fill_x: float, cy: float, f: float, dark: Color) -> void:
	if not track_colors.is_empty():
		_draw_gradient_track(Rect2(x0 - 6.0, cy - 4.0, (x1 - x0) + 12.0, 8.0))
		Liste.griff(self, Vector2(fill_x, cy), 10.0)
		Liste.griff(self, Vector2(fill_x, cy), 7.0, _gradient_at(_fill))
	else:
		draw_style_box(UzTheme.box(UzTheme.col("line"), 999), Rect2(x0, cy - 2.0, x1 - x0, 4.0))
		if fill_x > x0 + 0.5:
			draw_style_box(UzTheme.box(UzTheme.col("faint" if track_dim else "accent"), 999), Rect2(x0, cy - 2.0, maxf(fill_x - x0, 4.0), 4.0))
		Liste.griff(self, Vector2(fill_x, cy), 7.0 + 2.0 * _stell)
	var tr := Rect2(r.position.x + _track_w + 20.0, r.position.y, r.size.x - _track_w - 20.0, r.size.y)
	_draw_text_right(_shown, tr, _tone_color().lerp(UzTheme.col("text"), _stell).lerp(dark, f), 0.0, 1.0)


func _round_line(a: float, b: float, cy: float, h: float, c: Color) -> void:
	var rad := h * 0.5
	if b - a < 0.5:
		return
	draw_rect(Rect2(a, cy - rad, b - a, h), c)
	draw_circle(Vector2(a, cy), rad, c)
	draw_circle(Vector2(b, cy), rad, c)


func _gradient_at(t: float) -> Color:
	var n := track_colors.size()
	if n == 0:
		return UzTheme.col("accent")
	if n == 1:
		return track_colors[0]
	var x := clampf(t, 0.0, 1.0) * (n - 1)
	var i := mini(int(floor(x)), n - 2)
	return track_colors[i].lerp(track_colors[i + 1], x - i)


func _draw_gradient_track(r: Rect2) -> void:
	var n := track_colors.size()
	if n < 2:
		draw_rect(r, _gradient_at(0.0))
		return
	var rad := r.size.y * 0.5
	var x0 := r.position.x + rad
	var x1 := r.end.x - rad
	for i in n - 1:
		var a := lerpf(x0, x1, float(i) / (n - 1))
		var b := lerpf(x0, x1, float(i + 1) / (n - 1))
		draw_polygon(PackedVector2Array([Vector2(a, r.position.y), Vector2(b, r.position.y), Vector2(b, r.end.y), Vector2(a, r.end.y)]),
			PackedColorArray([track_colors[i], track_colors[i + 1], track_colors[i + 1], track_colors[i]]))
	draw_circle(Vector2(x0, r.get_center().y), rad, track_colors[0])
	draw_circle(Vector2(x1, r.get_center().y), rad, track_colors[n - 1])


func _draw_switch(r: Rect2, f: float, dark: Color) -> void:
	if UzTheme.strict():
		_draw_switch_eckig(r, f, dark)
		return
	var sw := Rect2(r.position + (r.size - SW_SIZE) * 0.5, SW_SIZE)
	var t := clampf(_knob, 0.0, 1.0)
	var off_track := UzTheme.col("text", 0.14).lerp(Color(dark, 0.2), f)
	var on_track := UzTheme.col("accent").lerp(dark, f)
	draw_style_box(UzTheme.box(off_track.lerp(on_track, t), int(minf(UzTheme.radius + 2, SW_SIZE.y * 0.5 - 0.5))), sw)
	var kw := SW_SIZE.y - 8.0
	# Unterwegs dehnt sich der Griff kurz – das gibt dem Umschalten Schwung.
	var stretch := sin(PI * t) * 9.0 if not is_equal_approx(t, 0.0) and not is_equal_approx(t, 1.0) else 0.0
	var travel := SW_SIZE.x - kw - 8.0
	var kx := sw.position.x + 4.0 + travel * t - stretch * t
	var off_knob := UzTheme.col("muted").lerp(Color(dark, 0.7), f)
	var on_knob := UzTheme.text_on(UzTheme.col("accent")).lerp(UzTheme.col("accent"), f)
	var kr := Rect2(kx, sw.position.y + 4.0, kw + stretch, kw)
	var rad := int(minf(maxf(1.0, UzTheme.radius), kw * 0.5 - 0.5))
	if t > 0.5:
		draw_style_box(UzTheme.box(Color(0, 0, 0, 0.16 * (1.0 - f)), rad), kr.grow(1.0))
	draw_style_box(UzTheme.box(off_knob.lerp(on_knob, t), rad), kr)


## Schalter der Listen-Sprache (wie im Guide, Liste.schalter): weiche Pille, der Griff gleitet, an
## liegt die Spur im Akzent; davor leise „An“ bzw. „Aus“.
func _draw_switch_eckig(r: Rect2, f: float, dark: Color) -> void:
	var t := clampf(_knob, 0.0, 1.0)
	var sw := Rect2(Vector2(r.end.x - SW_ECKIG.x, r.get_center().y - SW_ECKIG.y * 0.5), SW_ECKIG)
	Liste.schalter(self, sw, t)
	var txt := Rect2(r.position.x, r.position.y, r.size.x - SW_ECKIG.x - 14.0, r.size.y)
	_draw_text_right("An" if t >= 0.5 else "Aus", txt, UzTheme.col("muted").lerp(dark, f), 0.0, 1.0)

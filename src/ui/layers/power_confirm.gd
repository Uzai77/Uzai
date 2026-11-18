extends "res://src/ui/layers/dialog.gd"
## Confirmation before „PC ausschalten“ and „Neu starten“ (power menu, power_menu.gd), so the PC is not
## switched off by accident: the selection starts on „Abbrechen“, and confirming requires holding A –
## a ring in the button fills up in HALTEN_MS. A short press only shows the hint. If a game is running,
## the text says that it will end and unsaved progress will be lost.

const HALTEN_MS := 1000

var action := "shutdown"        ## "shutdown" | "restart"
var spiel := ""                 ## Titel des laufenden Spiels ("" = keins)
var on_confirm := Callable()

var _knopf: Button
var _ring: _Ring
var _hinweis: Label
var _haelt := false


## Titel, Satz und Knopf für die Rückfrage (ohne Bildschirm prüfbar).
static func texte(art: String, spiel_titel: String) -> Dictionary:
	var neu := art == "restart"
	return {
		"titel": "PC neu starten?" if neu else "PC ausschalten?",
		"satz": "Windows startet sofort neu." if neu else "Windows fährt sofort herunter.",
		# Eigene Zeile (übersetzt als Muster „%s wird beendet …“), leer ohne Spiel.
		"spiel": "%s wird beendet. Nicht gespeicherter Fortschritt geht verloren." % spiel_titel if spiel_titel != "" else "",
		"knopf": "Neu starten" if neu else "Ausschalten",
		"symbol": "restart" if neu else "power",
	}


## Anteil des Rings nach ms gehaltener Taste (0 … 1); 1 = bestätigt.
static func anteil(ms: int) -> float:
	return clampf(float(ms) / float(HALTEN_MS), 0.0, 1.0)


func fill() -> void:
	var t := texte(action, spiel)
	heading = str(t.titel)
	text = str(t.satz)
	icon_name = str(t.symbol)
	tone = "warn"
	# Nur „Abbrechen“ über den gewöhnlichen Weg (erster Knopf, Startauswahl); der gefährliche Knopf
	# kommt danach von Hand dazu, damit er auf Halten wartet.
	buttons = [["Abbrechen", Callable()]]
	width = 820.0
	dim = 0.8
	if _scrim:
		_scrim.color = Color(UzTheme.col("bg"), dim)
	var sb := UzTheme.box(UzTheme.col("surface"), UzTheme.r_panel(), 1, UzTheme.col("stroke"))
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	sb.content_margin_top = 44
	sb.content_margin_bottom = 40
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 44
	sb.shadow_offset = Vector2(0, 14)
	panel.add_theme_stylebox_override("panel", sb)
	box.add_child(_badge(icon_name, tone))
	var h := U.label(heading, "xl", "text", "title" if UzTheme.strict() else "black", true)
	h.custom_minimum_size = Vector2(width - 96.0, 0)
	box.add_child(h)
	var s := U.label(text, "m", "muted", "regular", true)
	s.custom_minimum_size = Vector2(width - 96.0, 0)
	box.add_child(s)
	if str(t.spiel) != "":
		var sp := U.label(str(t.spiel), "m", "warn", "medium", true)
		sp.custom_minimum_size = Vector2(width - 96.0, 0)
		box.add_child(sp)
	box.add_child(U.spacer(0, 10, false))
	var row := U.hbox(14)
	box.add_child(row)
	var ab: Button = Liste.knopf("Abbrechen", "", "primary") if UzTheme.strict() else U.button("Abbrechen", "", "primary")
	ab.set_meta("uz_default", true)
	ab.pressed.connect(close)
	row.add_child(ab)
	_knopf = Liste.knopf(str(t.knopf), "", "danger") if UzTheme.strict() else _danger_button(str(t.knopf))
	# Druck statt Loslassen: Maus und Controller starten das Halten im selben Augenblick.
	_knopf.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_knopf.set_meta("uz_hint_a", "Halten")
	_platz_rechts(_knopf, 44)
	_ring = _Ring.new()
	_ring.anchor_left = 1.0
	_ring.anchor_right = 1.0
	_ring.anchor_top = 0.5
	_ring.anchor_bottom = 0.5
	_ring.offset_left = -50.0
	_ring.offset_right = -24.0
	_ring.offset_top = -13.0
	_ring.offset_bottom = 13.0
	_knopf.add_child(_ring)
	_knopf.pressed.connect(_halten)
	row.add_child(_knopf)
	_hinweis = U.label("Zum Bestätigen gedrückt halten", "s", "faint", "medium")
	box.add_child(_hinweis)


## Rechts im Knopf Platz für den Ring (alle Zustände).
func _platz_rechts(b: Button, px: float) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var sb: StyleBox = b.get_theme_stylebox(st)
		if sb == null or sb is StyleBoxEmpty:
			continue
		var d: StyleBox = sb.duplicate()
		d.content_margin_right = sb.content_margin_right + px
		b.add_theme_stylebox_override(st, d)


static func _gedrueckt() -> bool:
	return Input.is_action_pressed("uz_a", true) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


## A (oder die Maus) wird gehalten: Der Ring füllt sich; los vor dem Ende → nichts, nur der Hinweis.
func _halten() -> void:
	if _haelt or _closing:
		return
	_haelt = true
	var t0 := Time.get_ticks_msec()
	while is_inside_tree() and not _closing and _gedrueckt():
		var f := anteil(Time.get_ticks_msec() - t0)
		_ring.set_anteil(f)
		if f >= 1.0:
			_haelt = false
			Sfx.play("select")
			var cb := on_confirm
			close()
			if cb.is_valid():
				cb.call()
			return
		await get_tree().process_frame
	_haelt = false
	if not is_inside_tree() or _closing:
		return
	_ring.set_anteil(0.0)
	Sfx.play("back")
	if is_instance_valid(_hinweis):
		_hinweis.add_theme_color_override("font_color", UzTheme.col("warn"))
		var tw := U.tw(_hinweis, "uz_halten")
		tw.tween_interval(1.4)
		tw.tween_callback(func() -> void:
			if is_instance_valid(_hinweis):
				_hinweis.add_theme_color_override("font_color", UzTheme.col("faint")))


## Ring im Knopf: leise als Kreis in Ruhe, füllt sich im Uhrzeigersinn, solange gehalten wird.
class _Ring extends Control:
	var frac := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_anteil(f: float) -> void:
		frac = f
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_arc(c, r, 0.0, TAU, 48, Color(UzTheme.col("text"), 0.28), 3.0, true)
		if frac > 0.0:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, UzTheme.col("text"), 3.0, true)

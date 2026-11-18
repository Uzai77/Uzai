extends "res://src/ui/layers/layer.gd"
## Lesemodus des Uzai-Browsers: nur der Text der Seite, groß und im Theme von Uzai – ohne Werbung, ohne
## Kopf und Seitenleiste der Seite, ohne Bilder. Der Text kommt vom Sprung-Skript als reiner Text
## (Schema geprüft, ohne Steuer- und Richtungszeichen) und wird nie als BBCode oder HTML gezeigt.
## Steuerkreuz, linker und rechter Stick rollen, B schließt. Y liest vor (Stimme des Systems, Windows: SAPI;
## nur Text dieser Seite, nie Adressen oder Code), Y noch einmal hält an – nur, wenn das System eine Stimme hat.

var titel := ""
var herkunft := ""
var absaetze: Array = []
var _sc: ScrollContainer
var _ziel := 0.0
var _liest := false
var _stimme := ""


func build() -> void:
	dim = 0.0
	var grund := ColorRect.new()
	grund.color = UzTheme.col("bg")
	U.full_rect(grund)
	grund.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grund)
	_sc = ScrollContainer.new()
	_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	U.full_rect(_sc)
	add_child(_sc)
	var mitte := CenterContainer.new()
	mitte.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sc.add_child(mitte)
	var col := U.vbox(26)
	col.custom_minimum_size = Vector2(1080, 0)
	mitte.add_child(col)
	col.add_child(U.spacer(0, 90, false))
	var h := U.label(herkunft, "s", "accent", "medium")
	h.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(h)
	var t := U.label(titel, "xxl", "text", "regular", true)
	t.add_theme_font_override("font", UzTheme.display())
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	t.custom_minimum_size.x = 1080
	col.add_child(t)
	col.add_child(U.spacer(0, 10, false))
	for a in absaetze:
		var l := U.label(str(a), "l", "text", "regular", true)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.custom_minimum_size.x = 1080
		l.add_theme_constant_override("line_spacing", 10)
		col.add_child(l)
	col.add_child(U.spacer(0, 160, false))
	var halt := Control.new()
	halt.focus_mode = Control.FOCUS_ALL
	halt.set_meta("uz_key", "browser:lesen")
	add_child(halt)
	set_meta("uz_hint_b", "Schließen")
	_stimme = stimme()
	if _stimme != "":
		set_meta("uz_hint_y", "Vorlesen")


## Eine Stimme des Systems für die Sprache von Uzai ("" wenn keine da ist oder Vorlesen aus ist).
static func stimme() -> String:
	if not bool(ProjectSettings.get_setting("audio/general/text_to_speech", false)):
		return ""
	var lang := TranslationServer.get_locale().substr(0, 2)
	var liste := DisplayServer.tts_get_voices_for_language(lang)
	if liste.is_empty():
		liste = DisplayServer.tts_get_voices_for_language("en")
	return str(liste[0]) if not liste.is_empty() else ""


func handle(cmd: String) -> bool:
	if cmd == "y" and _stimme != "":
		_vorlesen()
		return true
	return false


func _vorlesen() -> void:
	if _liest:
		DisplayServer.tts_stop()
		_liest = false
		set_meta("uz_hint_y", "Vorlesen")
		Nav.focus_moved.emit(Nav.focused())
		return
	var text := titel
	for a in absaetze:
		text += "\n" + str(a)
	_liest = true
	set_meta("uz_hint_y", "Anhalten")
	Nav.focus_moved.emit(Nav.focused())
	DisplayServer.tts_speak(text.left(20000), _stimme, 50, 1.0, 1.0, 0, false)


func close() -> void:
	if _liest:
		DisplayServer.tts_stop()
		_liest = false
	super.close()


func nav_dir(dir: String) -> bool:
	if dir in ["up", "down"]:
		_rollen((-1.0 if dir == "up" else 1.0) * 220.0)
	return true


func _rollen(d: float) -> void:
	var bar := _sc.get_v_scroll_bar()
	_ziel = clampf(maxf(_ziel, float(_sc.scroll_vertical)) + d if d > 0 else minf(_ziel, float(_sc.scroll_vertical)) + d, 0.0, bar.max_value)
	U.ankommen(_sc, U.T_ORT, "uz_lesen").tween_property(_sc, "scroll_vertical", int(_ziel), U.T_ORT)


func _process(dt: float) -> void:
	if Nav.top_layer() != self:
		return
	var v := 0.0
	for id in Input.get_connected_joypads():
		var a := Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y)
		if absf(a) > absf(v):
			v = a
	if absf(v) > 0.25:
		_sc.scroll_vertical += int(signf(v) * pow((absf(v) - 0.25) / 0.75, 1.6) * 2200.0 * dt)
		_ziel = float(_sc.scroll_vertical)

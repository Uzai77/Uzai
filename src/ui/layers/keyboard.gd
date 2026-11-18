extends "res://src/ui/layers/layer.gd"
## Bildschirmtastatur für den Controller (QWERTZ). Eine echte Tastatur tippt hier ebenfalls.
## X löscht, Y setzt ein Leerzeichen, LB/RB schieben die Schreibmarke einen Buchstaben nach
## links/rechts (Tippen und Löschen wirken dort), LT schaltet Großbuchstaben, RT die
## Sonderzeichen, Start bestätigt, B bricht ab – die Tasten dafür tragen das Zeichen des
## Controllers. Am Rand geht es auf der anderen Seite weiter (links aus der Reihe → rechts).
## „Handy“ zeigt einen QR-Code: auf dem Handy tippen oder einfügen, und der Text landet hier
## (praktisch für lange Schlüssel). „Einfügen“ nimmt die Zwischenablage.

signal done(text: String)
signal edited(text: String)     ## bei jeder Änderung (globale Suche: Treffer schon beim Tippen)

const QrView := preload("res://src/ui/components/qr_view.gd")
const Liste := preload("res://src/ui/components/liste.gd")

const ROWS := [
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "ß"],
	["q", "w", "e", "r", "t", "z", "u", "i", "o", "p", "ü"],
	["a", "s", "d", "f", "g", "h", "j", "k", "l", "ö", "ä"],
	["y", "x", "c", "v", "b", "n", "m", ",", ".", "-", "_"],
]
## Englisch: QWERTY wie auf englischen Tastaturen.
const ROWS_EN := [
	["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"],
	["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "'"],
	["a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "/"],
	["z", "x", "c", "v", "b", "n", "m", ",", ".", "?", "_"],
]
const SYMBOLS := [
	["!", "\"", "§", "$", "%", "&", "/", "(", ")", "=", "?"],
	["@", "#", "+", "*", "~", "'", "<", ">", "|", "{", "}"],
	[":", ";", "[", "]", "\\", "^", "°", "€", "²", "³", "`"],
	["é", "è", "à", "ñ", "ç", "ø", "å", "æ", "î", "ô", "û"],
]
const KEY := Vector2(92, 66)
const SEP := 8

var heading := ""
var text := ""
var caret := -1              ## Schreibmarke (Zeichen davor); -1: am Ende
var secret := false
var phone_link := ""         ## Link, den die Handy-Seite anbietet (z. B. „Schlüssel holen“)
var phone_ok := true         ## false: ohne „Handy“ (WLAN-Passwort – die Handy-Seite ist unverschlüsselt)
var see_through := false     ## nichts abdunkeln: darüber liegt etwas, das beim Tippen mitläuft (Suche)
var kuerzel: Array = []      ## Textstücke als eigene Tasten über dem Tastenfeld (Browser: „.com“, „www.“ – kuerzel_fuer)
var _kuerzel_row: HBoxContainer
var _phone_box: Control
var _req_id := ""
var _shift := false
var _symbols := false
var _field: Control
var _keys: GridContainer
var _shift_btn: Control
var _sym_btn: Control
var _bottom: HBoxContainer
var _panel: PanelContainer      ## das Tastenfeld: die Fläche der Ebene (Fläche vor Schrift)
var _lr_held := ""           ## LB/RB gedrückt gehalten: Schreibmarke wandert weiter
var _lr_next := 0
## Mit echter Tastatur oder Maus (Nav.device keys/mouse): ohne Tastenfeld – nur Feld, Hinweis und die Knöpfe unten.
## Links/Rechts schieben dann die Schreibmarke. Der Controller oder ein Finger klappt das Tastenfeld wieder auf.
var _kompakt := false
var _nur_tasten: Array = []   ## Teile, die es nur mit Tastenfeld gibt (Groß, #+=, Leerzeichen, ⌫)
var _tasten_btn: Control
var _kompakt_hinweis: Label


## Text snippets that this kind of input needs all the time, as their own keys (for example ".com" in the browser).
## art: "adresse" (address bar, a field for a URL) or "email"; otherwise none.
static func kuerzel_fuer(art: String) -> Array:
	var de := TranslationServer.get_locale().begins_with("de")
	match art:
		"adresse":
			return [".com", ".de" if de else ".net", ".org", ".net" if de else ".io", "www.", "https://"]
		"email":
			return ["@", ".com", ".de" if de else ".net", ".org"]
	return []


func build() -> void:
	dim = 0.0 if see_through else 0.72
	_scrim.color = Color(UzTheme.col("bg"), dim)
	set_meta("uz_hint_b", "Abbrechen")
	# Touch: jede Taste schon beim Aufsetzen, ohne langes Tippen (schnell mit zwei Daumen, zeiger.gd).
	set_meta("uz_tippen_sofort", true)
	caret = text.length() if caret < 0 or caret > text.length() else caret
	_cursor_hint()
	Nav.device_changed.connect(_on_device)
	var panel := PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface"), UzTheme.r_panel(), 1, UzTheme.col("stroke"))
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 30
	sb.content_margin_bottom = 32
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 48
	sb.shadow_offset = Vector2(0, 14)
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	var w := KEY.x * 11 + SEP * 10 + 72
	panel.offset_left = -w * 0.5
	panel.offset_right = w * 0.5
	panel.offset_bottom = -74
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(panel)
	_panel = panel
	var col := U.vbox(16)
	panel.add_child(col)
	var head := U.hbox(12)
	head.add_child(U.label(heading, "l", "text", "bold"))
	head.add_child(U.spacer())
	if secret:
		head.add_child(U.label("Wird verdeckt angezeigt", "s", "faint", "medium"))
	col.add_child(head)
	_field = _Field.new()
	_field.set("host", self)
	col.add_child(_field)
	_kompakt_hinweis = U.label("Einfach lostippen · Enter übernimmt · Esc bricht ab · Strg+V fügt ein", "s", "faint", "medium")
	col.add_child(_kompakt_hinweis)
	col.add_child(U.spacer(0, 2, false))
	if not kuerzel.is_empty():
		_kuerzel_row = U.hbox(SEP)
		for s in kuerzel.slice(0, 8):
			var stueck := str(s)
			var kt := _key(stueck, func() -> void: _type(stueck))
			kt.set("roh", true)
			kt.custom_minimum_size = Vector2(maxf(KEY.x, 34.0 + 15.0 * stueck.length()), 54)
			_kuerzel_row.add_child(kt)
		col.add_child(_kuerzel_row)
	_keys = GridContainer.new()
	_keys.columns = 11
	_keys.add_theme_constant_override("h_separation", SEP)
	_keys.add_theme_constant_override("v_separation", SEP)
	col.add_child(_keys)
	var bottom := U.hbox(SEP)
	_bottom = bottom
	col.add_child(bottom)
	_tasten_btn = _key("Bildschirmtastatur", func() -> void: _set_kompakt(false, true), 0, "keyboard")
	_tasten_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tasten_btn.set_meta("uz_hint_a", "Tasten zeigen")
	bottom.add_child(_tasten_btn)
	_shift_btn = _key("Groß", func() -> void: _toggle_shift(), 150, "", "lt")
	bottom.add_child(_shift_btn)
	_sym_btn = _key("#+=", func() -> void: _toggle_symbols(), 124, "", "rt")
	bottom.add_child(_sym_btn)
	var space := _key("Leerzeichen", func() -> void: _type(" "), 0, "", "y")
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(space)
	var weg := _key("⌫", func() -> void: _backspace(), 112, "", "x")
	bottom.add_child(weg)
	_nur_tasten = [_shift_btn, _sym_btn, space, weg]
	bottom.add_child(_key("Einfügen", func() -> void: _paste(), 140))
	if phone_ok:
		var phone := _key("Handy", func() -> void: _phone(), 134, "qr")
		phone.set_meta("uz_hint_a", "Mit dem Handy eingeben")
		bottom.add_child(phone)
	var ok := _key("Fertig", func() -> void: _finish(), 168, "check", "menu")
	ok.set("primary", true)
	ok.set_meta("uz_hint_a", "Übernehmen")
	# Ohne Tastenfeld (kompakt) steht die Auswahl hier; mit Tastenfeld gilt „q“ (früher in der Liste).
	ok.set_meta("uz_default", true)
	bottom.add_child(ok)
	_fill_keys()
	_set_kompakt(Nav.device in ["keys", "mouse"])
	_update_field()


## Tastenfeld weg (echte Tastatur, Maus) oder da (Controller, Touch). fokus: danach aufs Tastenfeld springen.
func _set_kompakt(an: bool, fokus := false) -> void:
	_kompakt = an
	_keys.visible = not an
	_kompakt_hinweis.visible = an
	_tasten_btn.visible = an
	for k in _nur_tasten:
		(k as Control).visible = not an
	if fokus and not an:
		await get_tree().process_frame
		var q := Nav.default_in(_keys)
		if q and is_inside_tree():
			Nav.focus(q, true)


## Fläche vor Schrift (layer.gd): Das Tastenfeld steht sofort deckend da, die Tasten kommen
## NACH_FLAECHE später.
func flaeche() -> Control:
	return _panel


## Die Tastatur steigt um W_ORT von unten auf (Kurve „Ankommen“, T_RAUM; sie wächst nach oben,
## also reicht der untere Rand).
func _enter_motion(fl: Control) -> void:
	var w := U.weg_px(U.W_ORT)
	if w == 0.0:
		return
	U.ankommen(fl, U.T_RAUM, "uz_tasten").tween_property(fl, "offset_bottom", -74.0, U.T_RAUM).from(-74.0 + w)


## Zu: um W_ORT nach unten, so lange wie die Ebene geht (T_WEG).
func _exit_motion(tw: Tween) -> void:
	tw.set_parallel(true)
	if is_instance_valid(_panel):
		U.stop(_panel, "uz_tasten")
		tw.tween_property(_panel, "position:y", _panel.position.y + U.weg_px(U.W_ORT), U.T_WEG)


func _key(label: String, cb: Callable, w := 0, icon := "", glyph := "") -> Control:
	var k := _Key.new()
	k.label = label
	k.cb = cb
	k.icon = icon
	k.glyph = glyph
	k.custom_minimum_size = Vector2(w if w > 0 else KEY.x, KEY.y)
	k.set_meta("uz_hint_a", "Tippen")
	k.host = self
	return k


func _fill_keys() -> void:
	var keep := -1
	var f := Nav.focused()
	if f and _keys.is_ancestor_of(f):
		keep = f.get_index()
	U.clear(_keys)
	var rows: Array = SYMBOLS if _symbols else (ROWS if TranslationServer.get_locale().begins_with("de") else ROWS_EN)
	var first: Control = null
	for row in rows:
		for k in row:
			var ch: String = k
			var shown := ch.to_upper() if _shift and not _symbols else ch
			var b := _key(shown, func() -> void: _type(shown))
			b.set("roh", true)
			_keys.add_child(b)
			if first == null and ch == "q":
				first = b
	if first:
		first.set_meta("uz_default", true)
	_shift_btn.set("on", _shift and not _symbols)
	_sym_btn.set("on", _symbols)
	_sym_btn.set("label", "abc" if _symbols else "#+=")
	if keep >= 0:
		await get_tree().process_frame
		if keep < _keys.get_child_count():
			Nav.focus(_keys.get_child(keep), true)


## Zeichen an der Schreibmarke einfügen (nicht nur am Ende).
func _insert(s: String) -> void:
	caret = clampi(caret, 0, text.length())
	text = text.left(caret) + s + text.substr(caret)
	caret += s.length()


func _type(ch: String) -> void:
	_insert(ch)
	if _shift and not _symbols:
		_shift = false
		_fill_keys()
	_update_field(true)


## Das Zeichen vor der Schreibmarke löschen.
func _backspace() -> void:
	caret = clampi(caret, 0, text.length())
	if caret > 0:
		text = text.left(caret - 1) + text.substr(caret)
		caret -= 1
		_update_field()


## Entf (echte Tastatur): das Zeichen hinter der Schreibmarke löschen.
func _delete_forward() -> void:
	caret = clampi(caret, 0, text.length())
	if caret < text.length():
		text = text.left(caret) + text.substr(caret + 1)
		_update_field()


## Schreibmarke um d Zeichen verschieben. Rückgabe: false, wenn sie schon am Rand stand.
func move_caret(d: int) -> bool:
	var to := clampi(caret + d, 0, text.length())
	if to == caret:
		return false
	caret = to
	_update_field()
	return true


func _paste() -> void:
	var clip := DisplayServer.clipboard_get().strip_edges()
	if clip != "":
		_insert(clip.replace("\n", " "))
		_update_field(true)
	else:
		Toasts.show_toast("Zwischenablage ist leer", "Am PC etwas kopieren oder „Handy“ wählen.", "keyboard", { "ms": 2500, "quiet": true })


## Eingabe übers Handy: QR-Code auf dem Fernseher, Text kommt über das Heimnetz.
## ip_override nur für Proben (ohne Heimnetz).
func _phone(ip_override := "") -> void:
	if _phone_box and is_instance_valid(_phone_box):
		return
	_req_id = "kb%d" % Time.get_ticks_msec()
	var url := Remote.phone_begin(_req_id, heading, "Text eintippen oder einfügen und senden. Er erscheint sofort in Uzai.", secret, phone_link, ip_override)
	if url == "":
		Toasts.show_toast("Kein Heimnetz gefunden", "Handy und PC müssen im selben WLAN sein.", "warning")
		return
	if not Remote.phone_text.is_connected(_on_phone_text):
		Remote.phone_text.connect(_on_phone_text)
	_phone_box = PanelContainer.new()
	var sb := UzTheme.box(UzTheme.col("surface"), UzTheme.r_panel(), 1, UzTheme.col("stroke"))
	sb.set_content_margin_all(30)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 40
	sb.shadow_offset = Vector2(0, 12)
	_phone_box.add_theme_stylebox_override("panel", sb)
	_phone_box.anchor_left = 0.5
	_phone_box.anchor_right = 0.5
	_phone_box.offset_left = -470
	_phone_box.offset_right = 470
	_phone_box.offset_top = 64
	add_child(_phone_box)
	var row := U.hbox(34)
	_phone_box.add_child(row)
	var qf := PanelContainer.new()
	var qsb := UzTheme.box(Color.WHITE, UzTheme.radius + 4)
	qsb.set_content_margin_all(6)
	qf.add_theme_stylebox_override("panel", qsb)
	qf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var qr = QrView.new()
	qr.setup(url, 236)
	qf.add_child(qr)
	row.add_child(qf)
	var col := U.vbox(12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	col.add_child(U.label("Mit dem Handy eingeben", "l", "text", "bold"))
	for step in ["Mit der Kamera des Handys den Code scannen.", "Tippen oder einfügen, dann „An Uzai senden“.", "Der Text erscheint sofort hier."]:
		var line := U.hbox(12)
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.draw.connect(func() -> void: dot.draw_circle(Vector2(4, 4), 3.5, UzTheme.col("accent"), true, -1.0, true))
		line.add_child(dot)
		var l := U.label(step, "m", "muted", "regular", true)
		l.custom_minimum_size = Vector2(520, 0)
		line.add_child(l)
		col.add_child(line)
	col.add_child(U.label("Handy und PC im selben WLAN · " + url.replace("http://", ""), "s", "faint", "medium"))
	_phone_box.modulate.a = 0.0
	var tw := U.im_tempo(create_tween()).set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(_phone_box, "modulate:a", 1.0, U.T_BASE)
	tw.tween_property(_phone_box, "offset_top", 64.0, U.T_MOVE).from(30.0)


func _on_phone_text(id: String, value: String) -> void:
	if id != _req_id:
		return
	text = value.strip_edges()
	caret = text.length()
	_update_field(true)
	if _phone_box and is_instance_valid(_phone_box):
		var box := _phone_box
		var tw := create_tween()
		tw.tween_property(box, "modulate:a", 0.0, U.T_BASE)
		tw.tween_callback(box.queue_free)
	_phone_box = null
	Toasts.show_toast("Vom Handy angekommen", "Mit Start oder „Fertig“ übernehmen.", "check")


func _exit_tree() -> void:
	if _req_id != "":
		Remote.phone_end(_req_id)
	if Remote.phone_text.is_connected(_on_phone_text):
		Remote.phone_text.disconnect(_on_phone_text)
	if Nav.device_changed.is_connected(_on_device):
		Nav.device_changed.disconnect(_on_device)


func _toggle_shift() -> void:
	_shift = not _shift
	_fill_keys()


func _toggle_symbols() -> void:
	_symbols = not _symbols
	_fill_keys()


func _update_field(typed := false) -> void:
	if _field:
		_field.call("refresh", typed)
	edited.emit(text)


func shown_text() -> String:
	return "•".repeat(text.length()) if secret else text


func _finish() -> void:
	done.emit(text)
	close()


func _input(event: InputEvent) -> void:
	# Echte Tastatur: Zeichen direkt übernehmen.
	if not (event is InputEventKey) or not event.pressed or Nav.top_layer() != self:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_BACKSPACE:
		_backspace()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_DELETE:
		_delete_forward()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_HOME or k.keycode == KEY_END:
		move_caret(-text.length() if k.keycode == KEY_HOME else text.length())
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		Sfx.play("select")
		_finish()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_V and k.ctrl_pressed:
		_paste()
		get_viewport().set_input_as_handled()
	elif _kompakt and (k.keycode == KEY_LEFT or k.keycode == KEY_RIGHT):
		# Ohne Tastenfeld gehören die Pfeile der Schreibmarke (wie in jedem Textfeld), nicht der Auswahl.
		move_caret(-1 if k.keycode == KEY_LEFT else 1)
		get_viewport().set_input_as_handled()
	elif k.unicode >= 32 and not k.ctrl_pressed and not k.alt_pressed:
		_type(char(k.unicode))
		get_viewport().set_input_as_handled()


func handle(cmd: String) -> bool:
	match cmd:
		"x":
			Sfx.play("tick")
			_backspace()
			return true
		"y":
			Sfx.play("tick")
			_type(" ")
			return true
		"lb", "rb":
			_step_caret(cmd)
			_lr_held = cmd
			_lr_next = Time.get_ticks_msec() + int(float(Config.get_value("controller.repeat_delay", 0.4)) * 1000.0)
			return true
		"lt":
			Sfx.play("tick")
			_toggle_shift()
			return true
		"rt":
			Sfx.play("tick")
			_toggle_symbols()
			return true
		"menu":
			Sfx.play("select")
			_finish()
			return true
	return false


## „LB RB Cursor“ unten in der Leiste – nur am Controller (auf der echten Tastatur tippen Q/E
## Buchstaben; dort schieben Pos1/Ende die Schreibmarke, Entf löscht dahinter).
func _cursor_hint() -> void:
	if Nav.device == "pad":
		set_meta("uz_hints", [["lb", ""], ["rb", "Cursor"]])
	elif has_meta("uz_hints"):
		remove_meta("uz_hints")


func _on_device(kind: String) -> void:
	_cursor_hint()
	# Zum Controller oder Finger gegriffen: das Tastenfeld klappt auf (umgekehrt bleibt es – wer es geöffnet hat, will es).
	if _kompakt and kind in ["pad", "touch"]:
		_set_kompakt(false, true)
	if Nav.top_layer() == self:
		Nav.focus_moved.emit(Nav.focused())


func _step_caret(cmd: String) -> void:
	Sfx.play("move" if move_caret(-1 if cmd == "lb" else 1) else "tick")


## LB/RB gedrückt halten: die Schreibmarke wandert weiter (Tempo wie beim Steuerkreuz).
func _process(_dt: float) -> void:
	if _lr_held == "":
		return
	if not Input.is_action_pressed("uz_" + _lr_held, true) or Nav.top_layer() != self:
		_lr_held = ""
		return
	var now := Time.get_ticks_msec()
	if now >= _lr_next:
		_lr_next = now + Nav.repeat_ms(4)
		if move_caret(-1 if _lr_held == "lb" else 1):
			Sfx.play("move")


# --- Steuerkreuz am Rand: auf der anderen Seite weiter ----------------------------------------

## Die Tasten in derselben Reihe wie k (Buchstabenreihe oder untere Leiste), von links nach rechts.
func _row_of(k: Control) -> Array:
	if k.get_parent() == _keys:
		var cols := _keys.columns
		var r := int(k.get_index() / float(cols))
		return _keys.get_children().slice(r * cols, r * cols + cols)
	if _bottom and k.get_parent() == _bottom:
		return _bottom.get_children().filter(func(c): return c is Control and (c as Control).visible)
	if is_instance_valid(_kuerzel_row) and k.get_parent() == _kuerzel_row:
		return _kuerzel_row.get_children()
	return []


## Links am linken Rand → rechts in derselben Reihe hinein (und umgekehrt).
func wrap_lr(k: Control, d: int) -> bool:
	var row := _row_of(k)
	var i := row.find(k)
	if i < 0 or row.size() < 2:
		return false
	if d < 0 and i == 0:
		Nav.focus(row[row.size() - 1])
		return true
	if d > 0 and i == row.size() - 1:
		Nav.focus(row[0])
		return true
	return false


## Hoch aus der obersten Reihe → untere Leiste, runter aus der Leiste → oberste Reihe (die Taste,
## die waagerecht am nächsten liegt). Mit Textstücken (kuerzel) sind sie die oberste Reihe.
func wrap_ud(k: Control, d: int) -> bool:
	var target: Array = []
	var stuecke: Array = _kuerzel_row.get_children() if is_instance_valid(_kuerzel_row) else []
	var unten: Array = _row_of(_bottom.get_child(0)) if _bottom and _bottom.get_child_count() > 0 else []
	if d < 0 and k.get_parent() == _keys and k.get_index() < _keys.columns:
		target = stuecke if not stuecke.is_empty() else unten
	elif d < 0 and not stuecke.is_empty() and k.get_parent() == _kuerzel_row:
		target = unten
	elif d > 0 and _bottom and k.get_parent() == _bottom and _keys.get_child_count() > 0:
		target = stuecke if not stuecke.is_empty() else _row_of(_keys.get_child(0))
	if target.is_empty():
		return false
	var cx := k.get_global_rect().get_center().x
	var best: Control = target[0]
	for c in target:
		if absf((c as Control).get_global_rect().get_center().x - cx) < absf(best.get_global_rect().get_center().x - cx):
			best = c
	Nav.focus(best)
	return true


## Das Eingabefeld: Text groß, eine weich blinkende Schreibmarke, ein leiser Platzhalter.
## Bei langem Text bleibt das Ende sichtbar.
class _Field extends Control:
	const UF := preload("res://src/ui/u.gd")
	var host: Node
	var _blink := 0.0
	var _pop := 0.0
	var _off := 0.0         ## so weit ist langer Text nach links gerollt (Schreibmarke bleibt sichtbar)

	func _ready() -> void:
		custom_minimum_size = Vector2(0, 86)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func refresh(typed: bool) -> void:
		_blink = 0.0
		if typed:
			var tw := UF.weg(self, "uz_pop")
			tw.tween_method(func(v: float) -> void:
				_pop = v
				queue_redraw()
			, 1.0, 0.0, UF.T_ORT)
		queue_redraw()

	func _process(dt: float) -> void:
		_blink += dt
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UzTheme.box(UzTheme.col("bg", 0.75), UzTheme.radius + 4, 1, UzTheme.col("stroke")), r)
		var t := str(host.call("shown_text")) if is_instance_valid(host) else ""
		var f := UzTheme.font("medium")
		var fs := UzTheme.size("xl")
		# Der getippte Text steht da, wie er ist – nie durch die Übersetzung: „Musik“ stünde im Englischen sonst als
		# „Music“ im Feld (übernommen würde trotzdem „Musik“), und die Schreibmarke säße daneben.
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := clampi(int(host.get("caret")) if is_instance_valid(host) else t.length(), 0, t.length())
		var cw := f.get_string_size(t.left(pos), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if pos < t.length() else tw
		var pad := 26.0
		var avail := size.x - pad * 2.0 - 8.0
		# Langer Text rollt nur so weit, dass die Schreibmarke im Feld bleibt.
		if tw > avail:
			_off = clampf(clampf(_off, cw - avail, cw), 0.0, tw - avail)
		else:
			_off = 0.0
		var x := pad - _off
		var base := (size.y - f.get_height(fs)) * 0.5 + f.get_ascent(fs)
		if t == "":
			draw_string(UzTheme.font("regular"), Vector2(pad, base), tr("Tippen …"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("faint", 0.8))
		else:
			draw_string(f, Vector2(x, base), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("text"))
		# Schreibmarke: weich ein- und ausblenden statt hart blinken; nach dem Tippen kurz kräftiger.
		var a := 0.55 + 0.45 * cos(_blink * TAU / 1.1)
		var cx := (x + cw + (4.0 if pos >= t.length() else -1.5)) if t != "" else pad - 2.0
		var ch := f.get_height(fs) * 0.82
		draw_rect(Rect2(cx, (size.y - ch) * 0.5, 3.0 + _pop * 1.5, ch), Color(UzTheme.col("accent"), clampf(a + _pop, 0.0, 1.0)))


## Eine Taste: ruhige Fläche ohne Rand, die Auswahl wächst hell auf. Funktionstasten tragen das
## Zeichen der Controller-Taste, die dasselbe tut. „Fertig“ ist der helle Hauptknopf.
class _Key extends Control:
	const UU := preload("res://src/ui/u.gd")

	var label := "":
		set(v):
			label = v
			if _l:
				_l.text = v
	var icon := ""
	var glyph := ""
	var roh := false         ## ein Zeichen der Tastatur (kein Wort): nie übersetzen
	var primary := false
	var on := false:
		set(v):
			on = v
			queue_redraw()
	var cb: Callable
	var host: Node           ## die Tastatur (Umlauf am Rand)
	var _l: Label

	## Steuerkreuz am Rand: Nav fragt erst die Taste selbst.
	func nav_lr(d: int) -> bool:
		return is_instance_valid(host) and bool(host.call("wrap_lr", self, d))

	func nav_ud(d: int) -> bool:
		return is_instance_valid(host) and bool(host.call("wrap_ud", self, d))

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		var cc := CenterContainer.new()
		UU.full_rect(cc)
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cc)
		var row := UU.hbox(10)
		cc.add_child(row)
		var ink := "on_focus" if primary else "text"
		if icon != "":
			var ic := UU.icon(icon, 24, ink)
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(ic)
		_l = UU.label(label, "l" if label.length() <= 2 else "m", ink, "ui_bold" if primary else "ui")
		_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if roh:
			_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.add_child(_l)
		if glyph != "":
			row.add_child(UU.glyph(glyph, 24))
		focus_entered.connect(func() -> void:
			if not primary:
				UU.etikett(self, true)
			else:
				UU.focus_anim(self, true)
			queue_redraw()
		)
		focus_exited.connect(func() -> void:
			if not primary:
				UU.etikett(self, false)
			else:
				UU.focus_anim(self, false)
			queue_redraw()
		)
		gui_input.connect(func(e: InputEvent) -> void:
			Nav.klick(self, e)
		)

	func activate() -> void:
		if cb.is_valid():
			cb.call()

	func activate_sound() -> String:
		return "select" if primary else "tick"

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var rad := maxi(3, UzTheme.radius - 2)
		var f: float = get_meta("uz_f", 1.0 if has_focus() else 0.0)
		if primary:
			if f > 0.01:
				var g := UzTheme.box(Color(0, 0, 0, 0), rad + 3)
				g.shadow_color = Color(UzTheme.col("accent"), 0.4 * f * UzTheme.glow_k())
				g.shadow_size = int(16 * f)
				draw_style_box(g, r)
			draw_style_box(UzTheme.box(UzTheme.col("sel"), rad), r)
			if f > 0.01:
				if UzTheme.cursor_frame():
					Liste.cursor(self, r, f)
				else:
					draw_style_box(UzTheme.box(Color(0, 0, 0, 0), rad + 3, 3, Color(UzTheme.col("focus").lightened(0.5), f)), r.grow(3))
			return
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.16 if on else 0.07), rad), r)
		# Derselbe Cursor wie in jeder Liste (liste.gd).
		Liste.zeilen_auswahl(self, rad)
		if on:
			# Eingerastet: ein kleiner Akzent unter der Beschriftung.
			var c := UzTheme.col("accent").lerp(UzTheme.col("on_focus"), f)
			draw_rect(Rect2(r.get_center().x - 12, r.end.y - 9, 24, 3), c)

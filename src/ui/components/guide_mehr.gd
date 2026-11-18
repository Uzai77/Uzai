extends VBoxContainer
## „Mehr …“ in der Guide-Leiste: klappt an Ort und Stelle auf, statt eine neue Ebene zu öffnen.
## Oben eine Zeile „Mehr …“ (leise dahinter, was drin steht), darunter die Zeilen. A klappt auf:
## die Zeilen schieben sich in T_ORT auf (Höhe und Deckkraft, „Ankommen“), der Pfeil dreht nach
## unten, die Auswahl springt auf die erste neue Zeile – ein Druck weniger. A an „Weniger“ klappt
## in T_WEG wieder zu (die Auswahl bleibt an der Zeile). Der Zustand steht im Guide (_folds), damit
## ein Neuaufbau wegen neuer Daten ihn behält; ein neuer Guide fängt zugeklappt an.

signal toggled(open: bool)

const U := preload("res://src/ui/u.gd")
const GuideRow := preload("res://src/ui/components/guide_row.gd")

const SUMMARY_MAX := 3           ## so viele Namen stehen leise hinter „Mehr …“

var key := "mehr"
var rows: Array = []
var open := false
var _head: GuideRow
var _chev: TextureRect
var _clip: Control
var _inner: VBoxContainer
var _tw: Tween


func setup(k: String, r: Array, is_open := false) -> Control:
	key = k
	rows = r
	open = is_open
	return self


## Was leise hinter „Mehr …“ steht: die ersten Namen, „…“ wenn es mehr sind (schon übersetzt).
static func summary(titles: Array) -> String:
	var names := PackedStringArray()
	for t in titles:
		if str(t) != "" and names.size() < SUMMARY_MAX:
			names.append(TranslationServer.translate(str(t)))
	if names.is_empty():
		return ""
	return ", ".join(names) + (" …" if titles.size() > SUMMARY_MAX else "")


func _titles() -> Array:
	var out: Array = []
	for r in rows:
		if r is Control and "title" in r and str(r.get("title")) != "":
			out.append(str(r.get("title")))
	return out


func _ready() -> void:
	add_theme_constant_override("separation", 2)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head = GuideRow.new().setup(_head_title(), "more", "" if open else summary(_titles()))
	_head.own_text = true
	_chev = U.icon("chevron_right", 20, "faint")
	_chev.pivot_offset = Vector2(10, 10)
	_chev.rotation = PI * 0.5 if open else 0.0
	_head.trail = _chev
	_head.set_meta("uz_key", "fold:" + key)
	_head.set_meta("uz_hint_a", "Zuklappen" if open else "Aufklappen")
	_head.activated.connect(toggle)
	add_child(_head)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_clip)
	_inner = U.vbox(2)
	_inner.anchor_right = 1.0
	_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_inner)
	for r in rows:
		if r is Control:
			_inner.add_child(r)
	_clip.visible = open
	if open:
		_clip.custom_minimum_size.y = _inner.get_combined_minimum_size().y
	_inner.minimum_size_changed.connect(func() -> void:
		if open and not (_tw and _tw.is_valid() and _tw.is_running()):
			_clip.custom_minimum_size.y = _inner.get_combined_minimum_size().y
	)


func _head_title() -> String:
	return TranslationServer.translate("Weniger" if open else "Mehr …")


## A an der Kopfzeile: auf- bzw. zuklappen.
func toggle() -> void:
	open = not open
	toggled.emit(open)
	_head.set_title(_head_title())
	_head.set_extra("" if open else summary(_titles()))
	_head.set_meta("uz_hint_a", "Zuklappen" if open else "Aufklappen")
	var h := _inner.get_combined_minimum_size().y
	var still := U.reduziert()
	if open:
		_clip.visible = true
		if still:
			_clip.custom_minimum_size.y = h
			_chev.rotation = PI * 0.5
		else:
			_clip.custom_minimum_size.y = 0.0
			_inner.modulate.a = 0.0
			_tw = U.ankommen(_clip, U.T_ORT, "uz_fold").set_parallel(true)
			_tw.tween_property(_clip, "custom_minimum_size:y", h, U.T_ORT)
			_tw.tween_property(_inner, "modulate:a", 1.0, U.T_ORT - U.NACH_FLAECHE).set_delay(U.NACH_FLAECHE)
			_tw.tween_property(_chev, "rotation", PI * 0.5, U.T_ORT)
		var first := Nav.default_in(_inner)
		if first:
			Nav.focus(first)
		else:
			Nav.focus_moved.emit(Nav.focused())
		return
	var f := Nav.focused()
	if f and _inner.is_ancestor_of(f):
		Nav.focus(_head)
	else:
		Nav.focus_moved.emit(Nav.focused())      # Hinweis „Aufklappen“ statt „Zuklappen“
	if still:
		_clip.custom_minimum_size.y = 0.0
		_clip.visible = false
		_chev.rotation = 0.0
		return
	_tw = U.weg(_clip, "uz_fold").set_parallel(true)
	_tw.tween_property(_clip, "custom_minimum_size:y", 0.0, U.T_WEG)
	_tw.tween_property(_inner, "modulate:a", 0.0, U.T_WEG)
	_tw.tween_property(_chev, "rotation", 0.0, U.T_WEG)
	_tw.chain().tween_callback(func() -> void:
		if not open:
			_clip.visible = false
			_inner.modulate.a = 1.0
	)


func head() -> Control:
	return _head

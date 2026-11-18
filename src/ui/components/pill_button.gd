extends Button
## Pille mit Tastensymbol vorn („A Spielen“, „Y Optionen“). Die Breite richtet sich nach Symbol
## und Wort, auch wenn das Symbol beim Gerätewechsel breiter wird (Tastatur: „Enter“).
## kind: "primary" (Hauptknopf: kräftigeres Glas, Symbol im Akzent), "flat" (Glas, gewählt hell)
## oder "danger" (rot getönt). Gewählt wird jeder hell, der Hauptknopf wächst dazu und glimmt.
## In der Marke derselbe ruhige Knopf wie überall (U.ruhig): echte Fläche, gewählt hell.

const U := preload("res://src/ui/u.gd")

var label_text := ""
var cmd := ""
var kind := "flat"
var icon_name := ""
var _box: HBoxContainer
var _label: Label
const PAD := Vector2(14, 0)
const PAD_R := 26


func setup(t: String, c := "", k := "flat", ic := "") -> Button:
	label_text = t
	cmd = c
	kind = k
	icon_name = ic
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	text = ""
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var primary := kind == "primary"
	var danger := kind == "danger"
	# Hauptknopf ruht als kräftigeres Glas (UzTheme "primary", siehe U.button), nur die Auswahl ist hell.
	var sb := UzTheme.box(UzTheme.col("primary") if primary else (Color(UzTheme.col("danger"), 0.18) if danger else UzTheme.col("glass_hi")), 999, 0 if primary
			else 1, UzTheme.col("stroke"))
	if primary:
		UzTheme.lift(sb, 1)
	var hv := sb.duplicate() as StyleBoxFlat
	hv.bg_color = UzTheme.col("sel") if primary else UzTheme.col("text", 0.16)
	var fo := UzTheme.cursor(UzTheme.with_glow(UzTheme.focus_fill(999), 1.8 if primary else 0.85), primary)
	add_theme_stylebox_override("normal", sb)
	add_theme_stylebox_override("hover", hv)
	add_theme_stylebox_override("pressed", hv)
	add_theme_stylebox_override("focus", fo)
	_box = U.hbox(10)
	add_child(_box)
	if cmd != "":
		_box.add_child(U.glyph(cmd, 28))
	var ink := "danger_text" if danger else "text"
	if icon_name != "":
		_box.add_child(U.icon(icon_name, 24, "accent_ink" if primary else ink))
	elif primary:
		# Ohne Symbol trägt die Schrift den Akzent (wie bei U.button).
		ink = "accent_ink"
	_label = U.label(label_text, "m", ink, "ui_bold")
	_label.clip_text = false
	_box.add_child(_label)
	_box.resized.connect(_fit)
	_fit()
	# Marke: derselbe ruhige Knopf wie überall (Fläche, gewählt hell; Wort und Symbol färbt er mit).
	if UzTheme.strict() and UzTheme.cursor_frame():
		U.ruhig(self, "danger" if danger else ("primary" if primary else ""), 0)
	focus_entered.connect(func() -> void: U.etikett(self, true))
	focus_exited.connect(func() -> void: U.etikett(self, false))


func set_icon(n: String) -> void:
	icon_name = n
	for c in _box.get_children():
		if c is TextureRect and c.has_meta("uz_icon"):
			(c as TextureRect).texture = Icons.tex(n, 24)


func _fit() -> void:
	var ms := _box.get_combined_minimum_size()
	var left := PAD.x if cmd != "" else (20.0 if icon_name != "" else float(PAD_R))
	custom_minimum_size = Vector2(left + ms.x + PAD_R, 56)
	_box.position = Vector2(left, (56 - ms.y) * 0.5)

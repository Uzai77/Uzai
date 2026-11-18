extends HBoxContainer
## Kleiner Hinweis „Mikro aus“ (Kopfleiste, Guide): steht da, solange das Mikrofon über Uzai, in
## Windows oder in Discord stumm ist (Mixer.mic_aus – derselbe Stand wie am Knopf „Mikro“), und
## blendet weich ein und aus.

const U := preload("res://src/ui/u.gd")

var px := 20                     ## Größe des Symbols
var kurz := false                ## nur das Symbol (Kopf des Guide: neben Glocke und Uhr ist kein Platz für das Wort)
var _an := false


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(U.icon("mic_off", px, "warn"))
	if not kurz:
		var l := U.label("Mikro aus", "s", "warn", "bold")
		l.clip_text = false
		add_child(l)
	_an = Mixer.mic_aus()
	visible = _an
	Mixer.mic_changed.connect(_on_mic)
	Voice.changed.connect(_on_voice)
	# Erscheint der Hinweis später (Guide), den Stand frisch nachsehen.
	Mixer.refresh_soon()


func _on_mic(_on: bool) -> void:
	_show(Mixer.mic_aus())


func _on_voice() -> void:
	_show(Mixer.mic_aus())


func _show(on: bool) -> void:
	if on == _an:
		return
	_an = on
	if on:
		visible = true
		modulate.a = 0.0
		U.tw(self, "uz_mic").tween_property(self, "modulate:a", 1.0, U.T_BASE)
	else:
		var tw := U.tw(self, "uz_mic")
		tw.tween_property(self, "modulate:a", 0.0, U.T_FAST)
		tw.tween_callback(func() -> void: visible = _an)

extends HBoxContainer
## Datenblock wie unten auf der Rückseite einer Spielhülle: Bezeichnung klein über dem Wert,
## Felder nebeneinander. Ersetzt Zeilen der Art „A · B · C“.

const U := preload("res://src/ui/u.gd")

var gap := 52


func _ready() -> void:
	add_theme_constant_override("separation", gap)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## fields: [[Bezeichnung, Wert], …]; leere Werte werden ausgelassen.
func set_fields(fields: Array) -> void:
	U.clear(self)
	for f in fields:
		if str(f[1]) == "":
			continue
		var v := U.vbox(0)
		var k := U.label(str(f[0]), "xs", "muted", "wide")
		k.clip_text = false
		v.add_child(k)
		var val := U.label(str(f[1]), "m", "text", "ui")
		val.clip_text = false
		v.add_child(val)
		add_child(v)

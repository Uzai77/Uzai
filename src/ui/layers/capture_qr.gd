extends "res://src/ui/layers/modal.gd"
## Aufnahme aufs Handy: QR-Code zu Uzais kleiner Seite im Heimnetz (wie „Eingabe per Handy“).
## Das Handy zeigt die Aufnahme und lädt sie herunter; teilen geht dann über das Handy – wie mit
## der PlayStation-App. Der Link gilt 30 Minuten und nur im selben WLAN.

const QrView := preload("res://src/ui/components/qr_view.gd")
const L := preload("res://src/core/capture_logic.gd")

var url := ""
var file := ""


func build() -> void:
	width = 1060.0
	set_meta("uz_hint_b", "Schließen")
	super()


func fill() -> void:
	var row := U.hbox(52)
	box.add_child(row)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UzTheme.box(Color.WHITE, UzTheme.radius + 4))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var qr = QrView.new()
	qr.setup(url, 340)
	frame.add_child(qr)
	row.add_child(frame)
	var col := U.vbox(16)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	col.add_child(U.label("An Handy senden", "xl", "text", "black"))
	var t := U.label("Mit der Handykamera scannen.", "m", "muted", "regular", true)
	t.custom_minimum_size = Vector2(540, 0)
	col.add_child(t)
	var name_l := U.label(file.get_file(), "m", "text", "bold", true)
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Dateiname (mit dem Namen des Spiels): nie übersetzen
	col.add_child(name_l)
	col.add_child(U.label(url.replace("http://", ""), "m", "accent", "medium"))
	var h := U.label("Nur im Heimnetz. 30 Minuten gültig.", "s", "faint", "regular", true)
	h.custom_minimum_size = Vector2(540, 0)
	col.add_child(h)
	var done := U.button("Fertig", "check", "primary")
	done.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	done.set_meta("uz_default", true)
	done.set_meta("uz_hint_a", "Schließen")
	done.pressed.connect(close)
	col.add_child(done)

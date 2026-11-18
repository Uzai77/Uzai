extends "res://src/ui/layers/modal.gd"
## Den laufenden Song aufs Handy holen: ein QR-Code mit dem Spotify-Link. Die Kamera des Handys
## öffnet ihn direkt in Spotify – auf dem PC springt dafür kein Browser auf.

const QrView := preload("res://src/ui/components/qr_view.gd")

var link := ""
var song := ""


func fill() -> void:
	width = 900.0
	var row := U.hbox(40)
	box.add_child(row)
	var frame := PanelContainer.new()
	var sb := UzTheme.box(Color.WHITE, UzTheme.radius + 4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	frame.add_theme_stylebox_override("panel", sb)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(frame)
	var qr = QrView.new()
	qr.setup(link, 300)
	frame.add_child(qr)
	var col := U.vbox(12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	col.add_child(U.label("Song aufs Handy", "xl", "text", "black", true))
	var s := U.label(song, "l", "muted", "medium", true)
	s.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Titel und Künstler: nie übersetzen
	s.max_lines_visible = 2
	col.add_child(s)
	col.add_child(U.spacer(0, 4, false))
	var t := U.label(
			"Mit der Handykamera scannen.", "m",
			"faint", "regular", true)
	t.custom_minimum_size = Vector2(440, 0)
	col.add_child(t)
	col.add_child(U.spacer(0, 10, false))
	var ok := U.button("Fertig", "check", "primary")
	ok.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ok.set_meta("uz_default", true)
	ok.pressed.connect(close)
	col.add_child(ok)

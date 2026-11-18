extends "res://src/ui/layers/modal.gd"
## Farbe wählen: fertige Töne oder Farbton, Sättigung, Helligkeit mit links/rechts. Die Schienen
## zeigen den Farbverlauf selbst, rechts oben steht die Farbe so, wie Uzai sie benutzt.

signal picked(color: Color)

const SWATCHES := ["#7aa2ff", "#4b6dff", "#5fd3d3", "#69e39a", "#a6e07c", "#f2b544", "#ff8a4c", "#ff5d78", "#e86fd6", "#a98bff", "#e4e4e7", "#8e96a8"]

var heading := ""
var color := Color.WHITE
const Main := preload("res://src/main.gd")
var main: Main
var _preview: Control
var _hex: Label
var _rows: Array = []
var _swatches: Array = []


func fill() -> void:
	width = 860
	box.add_child(U.label(heading, "xl", "text", "black"))
	var top := U.hbox(28)
	box.add_child(top)
	_preview = Control.new()
	_preview.custom_minimum_size = Vector2(132, 132)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, _preview.size)
		_preview.draw_style_box(UzTheme.box(color, UzTheme.r_panel() - 4, 1, UzTheme.col("stroke")), r)
	)
	top.add_child(_preview)
	var info := U.vbox(8)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	_hex = U.label("", "xl", "text", "medium")
	info.add_child(_hex)
	# So erscheint die Farbe in Uzai: Unterstrich unter einem Reiter, ein Fortschrittsbalken.
	var sample := Control.new()
	sample.custom_minimum_size = Vector2(420, 54)
	sample.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sample.draw.connect(func() -> void:
		var f := UzTheme.ui("ui")
		sample.draw_string(f, Vector2(0, 22), tr("Erfolge"), HORIZONTAL_ALIGNMENT_LEFT, -1, 21, UzTheme.col("text"))
		sample.draw_rect(Rect2(1, 31, 30, 3), color)
		sample.draw_string(f, Vector2(110, 22), tr("38 von 52"), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, UzTheme.col("muted"))
		sample.draw_style_box(UzTheme.box(UzTheme.col("text", 0.12), 3), Rect2(220, 14, 190, 6))
		sample.draw_style_box(UzTheme.box(color, 3), Rect2(220, 14, 190 * 0.73, 6))
		sample.draw_circle(Vector2(1 + 4, 48), 4.0, color, true, -1.0, true)
		sample.draw_string(f, Vector2(16, 53), tr("So steht die Farbe an Reitern, Balken und Markierungen."), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UzTheme.col("faint"))
	)
	_preview.set_meta("uz_sample", sample)
	info.add_child(sample)
	top.add_child(info)
	var sw := GridContainer.new()
	sw.columns = 12
	sw.add_theme_constant_override("h_separation", 12)
	sw.add_theme_constant_override("v_separation", 12)
	box.add_child(sw)
	for h in SWATCHES:
		var c := Color(h)
		var b := _Swatch.new()
		b.color = c
		b.host = self
		b.set_meta("uz_hint_a", "Nehmen")
		_swatches.append(b)
		sw.add_child(b)
	for spec in [["Farbton", "h"], ["Sättigung", "s"], ["Helligkeit", "v"]]:
		var r = SettingRow.new()
		var key: String = spec[1]
		r.setup("slider", spec[0], "", color.h if key == "h" else (color.s if key == "s" else color.v))
		r.min_v = 0.0
		r.max_v = 1.0
		r.step = 0.02 if key == "h" else 0.05
		r.fmt = "%d %%" if key != "h" else "%d°"
		r.fmt_scale = 100.0 if key != "h" else 360.0
		r.set_meta("uz_track", key)
		r.changed.connect(func(v: Variant) -> void:
			var hh := color.h
			var ss := color.s
			var vv := color.v
			match key:
				"h": hh = float(v)
				"s": ss = float(v)
				"v": vv = float(v)
			color = Color.from_hsv(hh, ss, vv)
			_sync(false)
		)
		_rows.append(r)
		box.add_child(r)
	var row := U.hbox(14)
	box.add_child(row)
	var ok := U.button("Übernehmen", "check", "primary")
	ok.pressed.connect(func() -> void:
		picked.emit(color)
		close()
	)
	row.add_child(ok)
	var hexb := U.button("Farbcode eingeben", "keyboard")
	hexb.pressed.connect(func() -> void:
		if main:
			main.open_keyboard("Farbcode, z. B. #7aa2ff", "#" + color.to_html(false), func(t: String) -> void:
				if t.strip_edges().is_valid_html_color():
					color = Color(t.strip_edges())
					_sync()
			)
	)
	row.add_child(hexb)
	# Startauswahl: der passende fertige Ton, sonst der Farbton.
	var start: Control = _rows[0]
	for b in _swatches:
		if (b.get("color") as Color).to_html(false) == color.to_html(false):
			start = b
	start.set_meta("uz_default", true)
	_sync()


func pick_swatch(c: Color) -> void:
	color = c
	_sync()


## Schienen als Farbverläufe: Farbton durch alle Farben, Sättigung von Grau zur Farbe,
## Helligkeit von Schwarz zur Farbe.
func _tracks() -> void:
	for r in _rows:
		var key := str(r.get_meta("uz_track", ""))
		var cols := PackedColorArray()
		match key:
			"h":
				for i in 7:
					cols.append(Color.from_hsv(i / 6.0, maxf(color.s, 0.55), maxf(color.v, 0.75)))
			"s":
				cols.append(Color.from_hsv(color.h, 0.0, color.v))
				cols.append(Color.from_hsv(color.h, 1.0, color.v))
			"v":
				cols.append(Color.from_hsv(color.h, color.s, 0.0))
				cols.append(Color.from_hsv(color.h, color.s, 1.0))
		r.track_colors = cols
		r.queue_redraw()


func _sync(rows := true) -> void:
	_hex.text = "#" + color.to_html(false)
	_preview.queue_redraw()
	var sample: Control = _preview.get_meta("uz_sample")
	sample.queue_redraw()
	for s in _swatches:
		(s as Control).queue_redraw()
	_tracks()
	if rows:
		var vals := [color.h, color.s, color.v]
		for i in _rows.size():
			_rows[i].value = vals[i]
			_rows[i]._refresh()


## Ein runder Farbknopf; der gerade gewählte trägt einen Haken.
class _Swatch extends Control:
	var color := Color.WHITE
	var host: Node

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(54, 54)
		focus_entered.connect(func() -> void:
			preload("res://src/ui/u.gd").focus_anim(self, true)
		)
		focus_exited.connect(func() -> void:
			preload("res://src/ui/u.gd").focus_anim(self, false)
		)
		gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				Nav.activate(self)
				accept_event()
		)

	func activate() -> void:
		if is_instance_valid(host):
			host.call("pick_swatch", color)

	func _draw() -> void:
		var f: float = get_meta("uz_f", 1.0 if has_focus() else 0.0)
		var c := size * 0.5
		if f > 0.01:
			draw_circle(c, 27.0 + 2.0 * f, Color(UzTheme.col("accent"), 0.22 * f), true, -1.0, true)
			draw_arc(c, 25.5 + 1.5 * f, 0, TAU, 48, Color(UzTheme.col("focus"), f), 3.0, true)
		draw_circle(c, 22.0 - 1.5 * f, color, true, -1.0, true)
		var cur: Color = host.get("color") if is_instance_valid(host) else Color.BLACK
		if cur.to_html(false) == color.to_html(false):
			var ck := UzTheme.text_on(color)
			draw_polyline(PackedVector2Array([c + Vector2(-7, 0.5), c + Vector2(-2, 5.5), c + Vector2(8, -5)]), ck, 3.0, true)

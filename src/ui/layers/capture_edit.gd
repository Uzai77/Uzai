extends "res://src/ui/layers/modal.gd"
## Clip bearbeiten mit dem Controller (Punkt 137): links das Bild an der gewählten Stelle mit dem
## Text, wie er im Clip stehen wird, rechts Zeitlupe, Text und Ton, darunter die Zeitleiste mit
## Bildstreifen. Links/rechts verschiebt den gewählten Griff (halten wird schneller: 0,5 s, dann
## 1 s, dann 5 s), LT/RT um eine Zehntelsekunde, A wechselt den Griff (Anfang, Ende, mit Zeitlupe
## auch deren Bereich). X spielt eine kleine Vorschau des Ergebnisses in Uzai ab, „Speichern“ legt
## eine neue Datei neben dem Original an – das bleibt immer. Logik: src/core/clip_edit.gd,
## Ausführen: Capture.edit_clip (läuft weiter, auch wenn diese Ebene zugeht).

const L := preload("res://src/core/capture_logic.gd")
const E := preload("res://src/core/clip_edit.gd")

const NAMES := { "a": "Anfang", "b": "Ende", "sa": "Zeitlupe ab", "sb": "Zeitlupe bis" }
const FRAME := Vector2(640, 360)

const Main := preload("res://src/main.gd")
var main: Main
var file := ""
var _dur := 0.0
var _audio := true
var _p := {}
var _sel := "a"
var _bar: _Bar
var _img: TextureRect
var _vid: VideoStreamPlayer
var _top_l: Label
var _bot_l: Label
var _badge: PanelContainer
var _badge_l: Label
var _wait: Label
var _info: Label
var _speed                       ## Einstellungszeilen (SettingRow)
var _top_r
var _bot_r
var _sound
var _btns: HBoxContainer
var _play_b: Button
var _save_b: Button
var _prog_box: HBoxContainer
var _prog: ProgressBarUz
var _prog_l: Label
var _stop_b: Button
var _reps := 0
var _last_ms := 0
var _gen := 0
var _pv_job := {}                 ## Vorschau wird gebaut (cancel bricht ab)
var _pv_file := ""
var _pv_sig := ""                 ## Plan der fertigen Vorschau
var _pv_plan := {}
var _playing := false
var _m_wartet := "Vorschau wird vorbereitet …  %d %%"      ## Muster der laufenden Zeilen, in fill() einmal übersetzt
var _m_speichert := "Wird gespeichert …  %d %%"


func build() -> void:
	width = 1240.0
	_dur = maxf(E.MIN_LEN, Capture.duration_of(file))
	_p = E.plan(_dur)
	if main == null:
		main = get_tree().current_scene
	super()


func fill() -> void:
	_m_wartet = tr(_m_wartet)
	_m_speichert = tr(_m_speichert)
	var head := U.hbox(16)
	head.add_child(U.label("Clip bearbeiten", "xl", "text", "black"))
	head.add_child(U.spacer())
	var name_l := U.label(str(L.parse_name(file).title), "m", "muted", "medium")
	name_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(name_l)
	box.add_child(head)

	var top := U.hbox(32)
	box.add_child(top)
	top.add_child(_build_frame())
	var col := U.vbox(8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(col)
	_speed = _row("choice", "Zeitlupe", "speed", "edit:speed")
	_speed.options = E.SPEEDS
	_speed.value = 1.0
	_speed.changed.connect(_on_speed)
	col.add_child(_speed)
	_top_r = _text_row("Text oben", "top")
	col.add_child(_top_r)
	_bot_r = _text_row("Text unten", "bottom")
	col.add_child(_bot_r)
	_sound = _row("toggle", "Ton", "volume", "edit:sound")
	_sound.value = true
	_sound.changed.connect(func(v: Variant) -> void:
		_p.mute = not bool(v)
		_update(false))
	col.add_child(_sound)

	_bar = _Bar.new()
	_bar.custom_minimum_size = Vector2(width - 96.0, 104)
	_bar.focus_mode = Control.FOCUS_ALL
	_bar.set_meta("uz_default", true)
	_bar.set_meta("uz_key", "edit:bar")
	_bar.set_meta("uz_hint_a", "Nächster Griff")
	_bar.set_meta("uz_hint_x", "Vorschau")
	_bar.set_meta("uz_on_x", _toggle_preview)
	_bar.activated.connect(_next_handle)
	box.add_child(_bar)
	_info = U.label("", "m", "muted", "medium")
	_info.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # ändert sich mit jedem Schritt: von Hand übersetzt
	box.add_child(_info)

	_btns = U.hbox(14)
	box.add_child(_btns)
	_play_b = U.button("Vorschau", "play")
	_play_b.set_meta("uz_key", "edit:play")
	_play_b.pressed.connect(_toggle_preview)
	_btns.add_child(_play_b)
	_save_b = U.button("Speichern", "check", "primary")
	_save_b.set_meta("uz_key", "edit:save")
	_save_b.pressed.connect(_save)
	_btns.add_child(_save_b)
	var cancel := U.button("Abbrechen")
	cancel.pressed.connect(close)
	_btns.add_child(cancel)

	_prog_box = U.hbox(18)
	_prog_box.visible = false
	box.add_child(_prog_box)
	_prog = ProgressBarUz.new().setup(0.0, "accent", 8, 0)
	_prog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prog.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_prog_box.add_child(_prog)
	_prog_l = U.label("", "m", "muted", "medium")
	_prog_l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_prog_box.add_child(_prog_l)
	_stop_b = U.button("Abbrechen", "close")
	_stop_b.set_meta("uz_key", "edit:stop")
	_stop_b.pressed.connect(func() -> void:
		if not Capture.edit_job.is_empty():
			Capture.edit_job["cancel"] = true)
	_prog_box.add_child(_stop_b)

	_update(true)
	_load()


func _build_frame() -> Control:
	var frame := Panel.new()
	frame.custom_minimum_size = FRAME
	frame.add_theme_stylebox_override("panel", UzTheme.box(Color.BLACK, UzTheme.r_cover()))
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_img = TextureRect.new()
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	U.full_rect(_img)
	frame.add_child(_img)
	_vid = VideoStreamPlayer.new()
	_vid.expand = true
	_vid.visible = false
	U.full_rect(_vid)
	_vid.finished.connect(_stop_preview)
	frame.add_child(_vid)
	# Text wie im fertigen Clip: ein Dreizehntel der Bildhöhe, gleicher Abstand oben und unten.
	var px := int(FRAME.y / E.TEXT_SIZE)
	_top_l = _overlay(px)
	_top_l.position = Vector2(0, FRAME.y * E.TEXT_TOP)
	frame.add_child(_top_l)
	_bot_l = _overlay(px)
	_bot_l.position = Vector2(0, FRAME.y * (1.0 - E.TEXT_BOTTOM) - px * 1.25)
	frame.add_child(_bot_l)
	_badge = U.panel("surface", 999, 0, 0.85)
	_badge.position = Vector2(16, 16)
	var bm := U.margin(14, 6, 16, 7)
	var bh := U.hbox(8)
	bh.add_child(U.icon("speed", 18, "accent"))
	_badge_l = U.label("", "s", "text", "medium")
	bh.add_child(_badge_l)
	bm.add_child(bh)
	_badge.add_child(bm)
	_badge.visible = false
	frame.add_child(_badge)
	_wait = U.label("", "m", "text", "medium")
	_wait.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED      # Zeile mit laufender Zahl
	_wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	U.full_rect(_wait)
	_wait.visible = false
	frame.add_child(_wait)
	return frame


func _overlay(px: int) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # eigener Text bleibt, wie er ist
	l.size = Vector2(FRAME.x, px * 1.3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.add_theme_font_override("font", UzTheme.font("regular"))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.visible = false
	return l


func _row(kind: String, t: String, icon: String, key: String):
	var r = SettingRow.new()
	r.setup(kind, t)
	r.compact = true
	r.icon_name = icon
	r.set_meta("uz_key", key)
	return r


func _text_row(t: String, k: String):
	# Rechts steht der eigene Text, so wie er im Clip landet: Die Zeile übersetzt nichts von selbst, Titel und
	# „Kein Text“ von Hand.
	var r = _row("action", tr(t), "edit", "edit:" + k)
	r.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	r.value_raw = true
	r.value_text = tr("Kein Text")
	r.set_meta("uz_hint_a", "Schreiben")
	r.set_meta("uz_hint_y", "Entfernen")
	r.set_meta("uz_on_y", func() -> void:
		_p[k] = ""
		r.set_value_text(tr("Kein Text"))
		_update(false))
	r.on_activate = func() -> void:
		if main == null:
			return
		main.open_keyboard(t, str(_p.get(k, "")), func(v: String) -> void:
			if not is_instance_valid(r):
				return
			_p[k] = E.clean_text(v)
			r.set_value_text(str(_p[k]) if str(_p[k]) != "" else tr("Kein Text"))
			_update(false))
	return r


## Länge, Ton und Bildstreifen von FFmpeg (beim ersten Öffnen eines fremden Clips dauert das kurz).
func _load() -> void:
	var info := await Capture.probe(file)
	if not is_inside_tree():
		return
	if float(info.duration) > 0.0 and absf(float(info.duration) - _dur) > 0.05:
		var whole := absf(float(_p.b) - _dur) < 0.05
		_dur = float(info.duration)
		if whole:
			_p.b = _dur
	_audio = bool(info.audio)
	if not _audio:
		_sound.kind = "info"
		_sound.value_text = "Kein Ton im Clip"
		_sound.call("_refresh")
	_update(true)
	var path := await Capture.strip(file)
	if path == "" or not is_inside_tree():
		return
	var img := Image.load_from_file(path)
	if img and not img.is_empty():
		_bar.strip = ImageTexture.create_from_image(img)
		_bar.strip_a = 0.0
		U.tw(_bar, "uz_strip").tween_property(_bar, "strip_a", 1.0, U.T_MOVE)


# --- Griffe ----------------------------------------------------------------------------------

func _handles() -> Array:
	return ["a", "b", "sa", "sb"] if E.has_slow(_p) else ["a", "b"]


func _next_handle() -> void:
	var hs := _handles()
	_sel = hs[(hs.find(_sel) + 1) % hs.size()]
	_update(true)


func nav_dir(cmd: String) -> bool:
	if not (cmd == "left" or cmd == "right") or Nav.focused() != _bar:
		return false
	var now := Time.get_ticks_msec()
	_reps = _reps + 1 if now - _last_ms < 260 else 0
	_last_ms = now
	_move(L.trim_step(_reps) * (-1.0 if cmd == "left" else 1.0))
	return true


func handle(cmd: String) -> bool:
	if (cmd == "lt" or cmd == "rt") and Nav.focused() == _bar:
		_move(E.FINE_S * (-1.0 if cmd == "lt" else 1.0))
		return true
	return false


func _move(d: float) -> void:
	var before := float(_p[_sel])
	_p[_sel] = before + d
	# Anfang/Ende schieben die Zeitlupe mit, damit sie im Clip bleibt.
	_p = E.clamp_plan(_p, _dur)
	Sfx.play("tick" if not is_equal_approx(before, float(_p[_sel])) else "bump")
	_update(true)


## Zeitlupe an: ihr Bereich steht schon im Clip (clamp_plan); A erreicht dann auch ihre Griffe.
func _on_speed(v: Variant) -> void:
	_p.speed = float(v)
	_update(true)


func _update(frame: bool) -> void:
	if not is_instance_valid(_bar):
		return
	_p = E.clamp_plan(_p, _dur)
	if not _sel in _handles():
		_sel = "a"
	_bar.dur = _dur
	_bar.p = _p
	_bar.sel = _sel
	_bar.queue_redraw()
	var t := float(_p[_sel])
	# Die Zeit des gewählten Griffs steht schon über ihm; hier das Ergebnis.
	_info.text = E.summary(_p, tr)
	_top_l.text = str(_p.top)
	_bot_l.text = str(_p.bottom)
	_top_l.visible = str(_p.top) != "" and not _playing
	_bot_l.visible = str(_p.bottom) != "" and not _playing
	_badge_l.text = "Zeitlupe %s" % E.speed_text(float(_p.speed))
	_badge.visible = E.has_slow(_p) and t >= float(_p.sa) - 0.01 and t <= float(_p.sb) + 0.01 and not _playing
	if _playing and JSON.stringify(_p) != _pv_sig:
		_stop_preview()
	if frame:
		_still(t)


## Bild an der Stelle (kurz gewartet, damit Halten nicht für jeden Schritt FFmpeg startet).
func _still(t: float) -> void:
	_gen += 1
	var g := _gen
	await get_tree().create_timer(0.25).timeout
	if g != _gen or not is_inside_tree() or not Capture.has_ffmpeg():
		return
	var out := Config.path("cache/captures/edit_%d.jpg" % (g % 2))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var r := await YouTube.exec(Capture.ffmpeg_path(), L.thumb_args(file, out, minf(t, maxf(0.0, _dur - 0.1))), 20.0)
	if g != _gen or not is_inside_tree() or not bool(r.get("ok", false)):
		return
	var img := Image.load_from_file(out)
	if img and not img.is_empty():
		_img.texture = ImageTexture.create_from_image(img)


# --- Vorschau --------------------------------------------------------------------------------

func _toggle_preview() -> void:
	if _playing:
		_stop_preview()
		return
	if not _pv_job.is_empty():
		_pv_job["cancel"] = true
		return
	if not Capture.has_ffmpeg():
		return
	var sig := JSON.stringify(_p)
	if sig != _pv_sig or not FileAccess.file_exists(_pv_file):
		_pv_job = { "cancel": false, "frac": 0.0 }
		_wait.text = tr("Vorschau wird vorbereitet …")
		_wait.visible = true
		_play_b.text = "Abbrechen"
		var plan := _p.duplicate()
		var path := await Capture.edit_preview(file, plan, _pv_job)
		if not is_inside_tree():
			return
		var cancelled := bool(_pv_job.get("cancel", false))
		_pv_job = {}
		_wait.visible = false
		_play_b.text = "Vorschau"
		if path == "":
			if not cancelled:
				Toasts.show_toast("Vorschau ging nicht", "Speichern geht trotzdem.", "warning", { "quiet": true })
			return
		_pv_file = path
		_pv_sig = JSON.stringify(plan)
		_pv_plan = plan
		if JSON.stringify(_p) != _pv_sig:
			return
	var stream := VideoStreamTheora.new()
	stream.file = _pv_file
	_vid.stream = stream
	_vid.visible = true
	_vid.play()
	_playing = true
	_play_b.text = "Anhalten"
	_play_b.icon = Icons.tex("pause", 26)
	_bar.set_meta("uz_hint_x", "Anhalten")
	_update(false)


func _stop_preview() -> void:
	if not _playing:
		return
	_playing = false
	_vid.stop()
	_vid.visible = false
	_play_b.text = "Vorschau"
	_play_b.icon = Icons.tex("play", 26)
	_bar.set_meta("uz_hint_x", "Vorschau")
	_bar.playhead = -1.0
	_update(false)


func _process(_dt: float) -> void:
	if _playing and is_instance_valid(_vid):
		_bar.playhead = E.src_at(_pv_plan, _vid.stream_position)
		_bar.queue_redraw()
	elif not _pv_job.is_empty():
		_wait.text = _m_wartet % int(float(_pv_job.get("frac", 0.0)) * 100.0)
	if is_instance_valid(_prog_box) and _prog_box.visible and not Capture.edit_job.is_empty():
		var f := float(Capture.edit_job.get("frac", 0.0))
		_prog.set_value(f)
		_prog_l.text = _m_speichert % int(f * 100.0)


# --- Speichern -------------------------------------------------------------------------------

func _save() -> void:
	if not E.is_changed(_p, _dur):
		Toasts.show_toast("Noch nichts geändert", "Anfang, Ende, Zeitlupe, Text oder Ton anpassen.", "edit", { "quiet": true, "ms": 2500 })
		return
	if not Capture.edit_job.is_empty():
		Toasts.show_toast("Es wird schon ein Clip bearbeitet", "Gleich noch einmal.", "clock", { "quiet": true, "ms": 2500 })
		return
	if Launcher.in_game:
		Toasts.show_toast("Erst das Spiel beenden", "Bearbeiten braucht Grafikkarte und Prozessor – das macht Uzai nicht neben einem Spiel.", "video")
		return
	_stop_preview()
	_btns.visible = false
	_prog_box.visible = true
	_prog.set_value(0.0)
	_prog_l.text = tr("Wird gespeichert …")
	Nav.focus(_stop_b, true)
	var out := await Capture.edit_clip(file, _p.duplicate())
	if not is_inside_tree():
		return
	if out != "":
		close()
		return
	_prog_box.visible = false
	_btns.visible = true
	Nav.focus(_save_b, true)


func close() -> void:
	if not _pv_job.is_empty():
		_pv_job["cancel"] = true
	if is_instance_valid(_vid):
		_vid.stop()
	super()


## Zeitleiste: Bildstreifen über die ganze Länge, außerhalb von Anfang–Ende abgedunkelt, die
## Zeitlupe getönt, die Griffe als helle Striche; der gewählte trägt seine Zeit darüber.
class _Bar extends Control:
	signal activated
	var dur := 1.0
	var p := {}
	var sel := "a"
	var strip: Texture2D
	var strip_a := 0.0:
		set(v):
			strip_a = v
			queue_redraw()
	var playhead := -1.0

	const BAND_Y := 34.0

	func _ready() -> void:
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func activate() -> void:
		activated.emit()

	func _x(t: float) -> float:
		return size.x * clampf(t / maxf(0.001, dur), 0.0, 1.0)

	func _draw() -> void:
		if p.is_empty():
			return
		var band := Rect2(0, BAND_Y, size.x, size.y - BAND_Y - 6)
		draw_style_box(UzTheme.box(UzTheme.col("text", 0.08), 10), band)
		if strip and strip_a > 0.0:
			draw_texture_rect(strip, band, false, Color(1, 1, 1, strip_a))
		var xa := _x(float(p.a))
		var xb := _x(float(p.b))
		var shade := Color(UzTheme.col("bg"), 0.72)
		draw_rect(Rect2(0, band.position.y, xa, band.size.y), shade)
		draw_rect(Rect2(xb, band.position.y, size.x - xb, band.size.y), shade)
		var slow := float(p.get("speed", 1.0)) < 1.0 and float(p.sb) - float(p.sa) >= 0.05
		if slow:
			var xs := _x(float(p.sa))
			var xe := _x(float(p.sb))
			draw_rect(Rect2(xs, band.position.y, xe - xs, band.size.y), UzTheme.col("accent", 0.22))
			draw_rect(Rect2(xs, band.end.y - 4, xe - xs, 4), UzTheme.col("accent", 0.9))
		# Rahmen um den behaltenen Teil.
		draw_rect(Rect2(xa, band.position.y, xb - xa, band.size.y), UzTheme.col("text", 0.9 if has_focus() else 0.55), false, 2.0)
		var hs := ["a", "b", "sa", "sb"] if slow else ["a", "b"]
		for h in hs:
			var x := _x(float(p[h]))
			var on: bool = h == sel
			var accent: bool = h == "sa" or h == "sb"
			var c := UzTheme.col("accent" if accent else "text", 1.0 if on and has_focus() else 0.6)
			var w := 8.0 if on else 4.0
			draw_style_box(UzTheme.box(c, 4), Rect2(x - w * 0.5, band.position.y - 6, w, band.size.y + 12))
		if playhead >= 0.0:
			var xp := _x(playhead)
			draw_rect(Rect2(xp - 1, band.position.y - 4, 2, band.size.y + 8), Color.WHITE)
		# Zeit des gewählten Griffs, über ihm (am Rand eingerückt).
		var font := UzTheme.font("medium")
		var txt := "%s  %s" % [tr(str(NAMES[sel])), E.time_text(float(p[sel]))]
		var fs := 22
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tx := clampf(_x(float(p[sel])) - tw * 0.5, 0.0, size.x - tw)
		draw_string(font, Vector2(tx, 24), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UzTheme.col("text" if has_focus() else "muted"))

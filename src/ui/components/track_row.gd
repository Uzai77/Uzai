extends Control
## Ein Titel in Musiklisten: kleines Albumbild, Titel und Interpret, Album, Dauer. Läuft der
## Titel gerade, zeigt das Bild einen kleinen Pegel und der Name leuchtet in der Musikfarbe.

signal chosen(track: Dictionary)

const U := preload("res://src/ui/u.gd")
const Liste := preload("res://src/ui/components/liste.gd")

const H := 74
const ART := 52

var track: Dictionary = {}
var number := 0                 ## 1, 2, 3 … (0: keine Nummer)
var show_album := true
var show_art := true            ## Albumbild links (in einem Album überall gleich: dann aus)
var _tex: Texture2D
var _t := 0.0
var _lage := -1                 ## zuletzt gezeichnet: 0 nicht dran, 1 dran und still, 2 läuft (-1: noch nie)


func setup(t: Dictionary, n := 0) -> Control:
	track = t
	number = n
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, H)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_meta("uz_key", "tr:" + str(track.get("uri", "")) + ":" + str(number))
	var url := str(track.get("art", ""))
	if url != "" and show_art:
		Media.url_texture(url, 128, func(t: Texture2D) -> void:
			if is_instance_valid(self):
				_tex = t
				queue_redraw()
		)
	focus_entered.connect(func() -> void: U.focus_anim(self, true))
	focus_exited.connect(func() -> void: U.focus_anim(self, false))
	Music.updated.connect(_on_music)
	_on_music()
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)


func is_current() -> bool:
	var uri := str(track.get("uri", ""))
	return uri != "" and uri == str(Music.now.get("uri", ""))


## Music.updated kommt alle paar Sekunden und bei jedem Tastendruck: Neu zeichnet nur die Zeile, bei
## der sich etwas geändert hat (eine Playlist hat bis zu 500 davon).
func _on_music() -> void:
	var lage := 0
	if is_current():
		lage = 2 if bool(Music.now.get("playing", false)) else 1
	set_process(lage == 2)
	if lage != _lage:
		_lage = lage
		queue_redraw()


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


func activate() -> void:
	chosen.emit(track)


func _draw() -> void:
	var f := float(get_meta("uz_f", 0.0)) if has_meta("uz_f") else 0.0
	Liste.zeilen_auswahl(self, UzTheme.radius)
	var on_focus := f > 0.5
	var ink := UzTheme.col("on_focus") if on_focus else UzTheme.col("text")
	var soft := Color(ink, 0.62)
	var cur := is_current()
	var x := 16.0
	var font := UzTheme.font("medium")
	var bold := UzTheme.font("bold")
	if number > 0:
		if not (cur and not show_art):
			var ns := str(number)
			var nw := font.get_string_size(ns, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			draw_string(font, Vector2(x + 30 - nw, H * 0.5 + 6), ns, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(soft, 0.8))
		x += 46
	var ar := Rect2(x, (H - ART) * 0.5, ART if show_art else 0.0, ART)
	if show_art:
		# Platzhalter in der Farbe der Schrift: auf der hellen Auswahl dunkel, sonst hell.
		draw_style_box(UzTheme.box(Color(ink, 0.09), 8), ar)
		if _tex:
			draw_texture_rect(_tex, ar.grow(-0.5), false)
		else:
			var ic := Icons.tex("music", 22)
			draw_texture_rect(ic, Rect2(ar.get_center() - Vector2(11, 11), Vector2(22, 22)), false, Color(ink, 0.38))
	if cur and not show_art:
		# Ohne Bild: der Pegel steht an der Stelle der Nummer.
		var playing0 := bool(Music.now.get("playing", false))
		for i in 3:
			var h0 := 6.0 + (absf(sin(_t * (5.0 + i * 1.7) + i)) * 12.0 if playing0 else 3.0 + i * 3.0)
			draw_rect(Rect2(x - 40 + i * 7, H * 0.5 + 9 - h0, 4, h0), UzTheme.col("music") if not on_focus else ink)
	elif cur:
		# Kleiner Pegel über dem Bild, solange der Titel läuft.
		draw_style_box(UzTheme.box(Color(0, 0, 0, 0.55), 8), ar)
		var playing := bool(Music.now.get("playing", false))
		for i in 3:
			var h := 8.0 + (absf(sin(_t * (5.0 + i * 1.7) + i)) * 14.0 if playing else 4.0 + i * 3.0)
			draw_rect(Rect2(ar.get_center().x - 10 + i * 8, ar.get_center().y + 10 - h, 4, h), UzTheme.col("music"))
	x = ar.end.x + (18 if show_art else 4)
	# Ohne bekannte Länge (eigener Verlauf) keine „0:00“.
	var dur := _fmt(int(track.get("duration", 0))) if int(track.get("duration", 0)) > 0 else ""
	# Titel, Künstler und Album sind fremde Namen: nie übersetzen (kein tr()).
	var dw := font.get_string_size(dur, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var right := size.x - 22
	draw_string(font, Vector2(right - dw, H * 0.5 + 6), dur, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, soft)
	right -= dw + 34
	var album_w := 0.0
	if show_album and size.x > 900:
		album_w = minf(360.0, size.x * 0.28)
		draw_string(font, Vector2(right - album_w, H * 0.5 + 6), str(track.get("album_line", track.get("album", ""))), HORIZONTAL_ALIGNMENT_LEFT, album_w, 17,
				soft, TextServer.JUSTIFICATION_NONE)
		right -= album_w + 30
	var tw := right - x
	var title_col := ink
	if cur and not on_focus:
		title_col = UzTheme.col("music")
	var title := str(track.get("title", ""))
	draw_string(bold, Vector2(x, H * 0.5 - 4), title, HORIZONTAL_ALIGNMENT_LEFT, tw, 20, title_col, TextServer.JUSTIFICATION_NONE)
	var sub := str(track.get("artist", ""))
	var sx := x
	if track.get("explicit", false):
		var er := Rect2(sx, H * 0.5 + 4, 20, 20)
		draw_style_box(UzTheme.box(Color(ink, 0.5), 3), er)
		var efs := UzTheme.size("cap")
		draw_string(bold, Vector2(sx + (20.0 - bold.get_string_size("E", HORIZONTAL_ALIGNMENT_LEFT, -1, efs).x) * 0.5, H * 0.5 + 20), "E",
				HORIZONTAL_ALIGNMENT_LEFT, -1, efs, UzTheme.col("on_focus") if not on_focus else UzTheme.col("text"))
		sx += 26
	draw_string(font, Vector2(sx, H * 0.5 + 20), sub, HORIZONTAL_ALIGNMENT_LEFT, right - sx, 17, soft, TextServer.JUSTIFICATION_NONE)


static func _fmt(ms: int) -> String:
	var s := ms / 1000
	return "%d:%02d" % [s / 60, s % 60]

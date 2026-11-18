extends Control
## Ersatz-Cover, wenn es noch kein Bild gibt: Farbe des Systems, ein Muster pro System
## und der Titel in großer Schrift – wie ein Etikett auf einer Spielhülle.

var title := ""
var system_id := ""
var system_short := ""
var base_color := Color("#2a2f3d")
var compact := false
var show_title := true       ## aus, wenn der Titel ohnehin daneben steht (Guide, Für dich)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func setup(game: Dictionary) -> void:
	title = str(game.get("title", "?"))
	system_id = str(game.get("system", ""))
	var sys := Config.system(system_id)
	if not sys.is_empty():
		base_color = Color(str(sys.get("color", "#2a2f3d")))
		system_short = str(sys.get("name", sys.get("short", system_id)))
	elif system_id == "steam":
		base_color = Color("#1b2838")
		system_short = "Steam"
	elif system_id == "epic":
		base_color = Color("#202226")
		system_short = "Epic Games"
	elif system_id == "ea":
		base_color = Color("#3a1d24")
		system_short = "EA app"
	elif Library.Stores.is_extra(system_id):
		base_color = Color(Library.Stores.color_of(system_id))
		system_short = Library.Stores.name_of(system_id)
	else:
		base_color = Color("#2b2d33")
		system_short = "PC"
	# Leichte Variation pro Spiel, damit eine Reihe nicht einfarbig wirkt.
	var h := float(title.hash() % 1000) / 1000.0
	base_color = base_color.lerp(base_color.lightened(0.18) if h > 0.5 else base_color.darkened(0.25), absf(h - 0.5) * 0.9)
	queue_redraw()


## Wie eine Hülle: links der Rücken mit dem System (gedreht), rechts die Vorderseite mit Titel.
func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, base_color)
	var ink := UzTheme.text_on(base_color)
	var spine := maxf(16.0, roundf(size.x * 0.12))
	var front := Rect2(spine, 0, size.x - spine, size.y)
	var faint := Color(ink, 0.07)
	var pattern := absi(system_id.hash()) % 5
	match pattern:
		0:
			var y := 6.0
			while y < size.y:
				draw_line(Vector2(front.position.x, y), Vector2(size.x, y), faint, 1.0)
				y += 7.0
		1:
			var x := front.position.x + 10.0
			while x < size.x:
				draw_line(Vector2(x, 0), Vector2(x, size.y), faint, 1.0)
				x += 14.0
		2:
			var yy := 10.0
			while yy < size.y:
				var xx := front.position.x + 10.0
				while xx < size.x:
					draw_circle(Vector2(xx, yy), 1.6, faint)
					xx += 16.0
				yy += 16.0
		3:
			var d := front.position.x - size.y
			while d < size.x:
				draw_line(Vector2(maxf(d, front.position.x), size.y - maxf(0.0, front.position.x - d)), Vector2(d + size.y, 0), faint, 1.0)
				d += 18.0
		4:
			var c := Vector2(size.x * 0.85, size.y * 0.2)
			var rad := 18.0
			while rad < size.length():
				draw_arc(c, rad, 0, TAU, 64, faint, 1.0, true)
				rad += 16.0
	# Rücken: dunkler Streifen, darauf das System von unten nach oben gelesen.
	draw_rect(Rect2(0, 0, spine, size.y), base_color.darkened(0.38))
	draw_rect(Rect2(spine - 1, 0, 1, size.y), Color(ink, 0.12))
	var wide := UzTheme.ui("wide")
	var fs_s := int(clampf(spine * 0.52, 10, 16))
	draw_set_transform(Vector2(spine * 0.5 + fs_s * 0.36, size.y - 12), -PI * 0.5, Vector2.ONE)
	draw_string(wide, Vector2.ZERO, tr(system_short), HORIZONTAL_ALIGNMENT_LEFT, size.y - 24, fs_s, Color(ink, 0.82))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if size.x < 130.0 or not show_title:
		return
	var pad := 16.0 if not compact else 10.0
	var font := UzTheme.display("black")
	var fs := 32 if not compact else 21
	if title.length() > 28:
		fs -= 5
	var avail := front.size.x - pad * 2
	# Nie mitten im Wort trennen („Cyberpun k“): lieber die Schrift etwas kleiner setzen, bis
	# das längste Wort in die Zeile passt. Nur wenn selbst das nicht reicht, darf Godot trennen.
	var fit := fit_size(title, font, fs, 20 if not compact else 13, avail)
	var para := TextParagraph.new()
	para.width = avail
	para.max_lines_visible = 4
	para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	if fit < 0:
		para.break_flags |= TextServer.BREAK_ADAPTIVE
	fs = absi(fit)
	para.line_spacing = -fs * 0.28
	para.add_string(title, font, fs)
	var h := para.get_size().y
	para.draw(get_canvas_item(), Vector2(front.position.x + pad, size.y - pad - 4 - h), ink)


## Größte Schrift (von start abwärts bis min_fs), bei der das längste Wort in width passt.
## Negativ, wenn es selbst bei min_fs nicht passt (dann muss im Wort getrennt werden).
static func fit_size(text: String, font: Font, start: int, min_fs: int, width: float) -> int:
	var words := text.split(" ", false)
	var fs := start
	min_fs = mini(min_fs, start)
	while fs > min_fs:
		if _longest(words, font, fs) <= width:
			return fs
		fs -= 1
	return min_fs if _longest(words, font, min_fs) <= width else -min_fs


static func _longest(words: PackedStringArray, font: Font, fs: int) -> float:
	var longest := 0.0
	for w in words:
		longest = maxf(longest, font.get_string_size(TranslationServer.translate(w), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return longest

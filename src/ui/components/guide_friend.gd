extends Control
## Eine Person in der Guide-Leiste (Reiter Freunde, „Mehr …“ › Mehrspieler): Bild mit Zustand,
## Name und was sie gerade macht; rechts ein Schild für die offene Lobby, ungelesene Nachrichten,
## der Sprachkanal und – nur in gemischten Listen – ein kleines Zeichen der Quelle. A öffnet das
## Menü an der Person. compact: Zeile für „Mehr …“ (sagt, was man zusammen tun kann).
## hold hält den Cursor, solange das Menü an der Zeile offen ist.

signal chosen(entry: Dictionary)

const U := preload("res://src/ui/u.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")
const People := preload("res://src/ui/components/guide_people.gd")
const GuideRow := preload("res://src/ui/components/guide_row.gd")

var entry: Dictionary = {}
var game_title := ""            ## Spiel, wie es in der Bibliothek heißt (sonst wie gemeldet)
var compact := false
var show_source := false        ## Steam/Discord-Zeichen zeigen (gemischte Liste)
var hold := false:
	set(v):
		hold = v
		if is_inside_tree():
			_focus_to(v or has_focus())
var _f := 0.0


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_meta("uz_key", "fr:" + str(entry.get("key", "")))
	var m := U.margin(0, 4, 0, 4)
	U.full_rect(m)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	var row := U.hbox(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	var game := game_title if game_title != "" else str(entry.get("game", ""))
	var line := _compact_line() if compact else (game if game != "" else People.doing(entry))
	var av := Avatar.new()
	av.setup(str(entry.get("name", "?")), str(entry.get("avatar", "")), People.dot(entry), 44 if line != "" else 36)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(av)
	var col := U.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var nl := U.ellipsis(U.label(str(entry.get("name", "?")), "20", "text", "ui_bold"))
	nl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # Namen bleiben, wie sie sind
	col.add_child(nl)
	if not compact and game != "":
		# Discord meldet oft mehr (Rich Presence): „Elden Ring · Limgrave“.
		var dm: Dictionary = entry.get("dm", {}) if entry.get("dm") is Dictionary else {}
		var more := str(dm.get("details", ""))
		if more == "":
			more = str(dm.get("activity_state", ""))
		if more != "":
			line += "  ·  " + more
	var sl := U.ellipsis(U.label(line, "16", "muted", "regular"))
	if game != "" and not compact:
		sl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	col.add_child(sl)
	# Rechts: Zeichen, die man aus drei Metern erkennt.
	var badges := U.hbox(10)
	badges.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badges)
	if not compact and str(entry.get("join_url", "")) != "":
		badges.add_child(_Pill.new().setup("Lobby", "line", self))
	if str(entry.get("voice_id", "")) != "":
		var hs := U.icon("headset", 18, "muted")
		hs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badges.add_child(hs)
	if int(entry.get("unread", 0)) > 0:
		badges.add_child(_Pill.new().setup(str(int(entry.unread)), "fill", self))
	if show_source:
		# The source's real logo, small and monochrome, without a wordmark (otherwise "Discord" could
		# appear up to three times). Until it has loaded, the previous icon is shown.
		badges.add_child(_Logo.new().setup(People.source(entry)))
	custom_minimum_size = Vector2(0, 58 if line != "" else 48)
	focus_entered.connect(_focus_to.bind(true))
	focus_exited.connect(func() -> void: _focus_to(hold))
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)


## In „Mehr …“ zählt, was man zusammen tun kann.
func _compact_line() -> String:
	if str(entry.get("join_url", "")) != "":
		return "Lobby offen"
	if bool(entry.get("with_me", false)):
		return "Mit dir im Sprachkanal"
	if int(entry.get("unread", 0)) > 0:
		return U.plural(int(entry.unread), "neue Nachricht", "neue Nachrichten")
	return "Spielt gerade mit"


## Der eine Cursor-Takt (Liste.takt): im ersten Bild zu 70 % da, gesetzt in T_ANTWORT.
func _focus_to(on: bool) -> void:
	GuideRow.Liste.takt(self, _f, on, func(v: float) -> void:
		_f = v
		queue_redraw())


func activate() -> void:
	chosen.emit(entry)


func _draw() -> void:
	GuideRow.draw_cursor(self, Rect2(-GuideRow.OUT, 0, size.x + GuideRow.OUT * 2.0, size.y), _f)


## Kleines eckiges Schild rechts in der Zeile: „Lobby“ (Rand im Akzent) oder die Zahl ungelesener
## Nachrichten (gefüllt im Akzent).
## Logo von Steam bzw. Discord (BadgeLogos: zur Laufzeit von Wikimedia, privat im Cache, R4),
## einfarbig in der leisen Schriftfarbe, 18 Punkte hoch. Einmal je Sitzung im Hintergrund vorbereitet.
class _Logo extends TextureRect:
	const Arbeit := preload("res://src/core/arbeit.gd")
	const Logos := preload("res://src/core/badge_logos.gd")
	const H := 18.0
	static var _fertig := {}            ## Schlüssel -> Texture2D (einfarbig)
	static var _arbeit := {}            ## Schlüssel -> Arbeit.Auftrag (Vorbereitung läuft oder ist durch)
	var art := ""

	func setup(a: String) -> Control:
		art = a
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		modulate = UzTheme.col("muted")
		_zeigen()
		return self

	func _zeigen() -> void:
		var t: Texture2D = _fertig.get(art)
		if t:
			texture = t
			custom_minimum_size = Vector2(roundf(H * float(t.get_width()) / maxf(1.0, float(t.get_height()))), H)
			set_process(false)
			return
		# Noch nicht da: das bisherige Zeichen und das Logo vorbereiten bzw. holen.
		texture = Icons.tex(art, int(H))
		custom_minimum_size = Vector2(H, H)
		if not Logos.enabled():
			return
		if FileAccess.file_exists(Logos.cache_path(art)):
			if not _arbeit.has(art):
				_arbeit[art] = Arbeit.auftrag(_vorbereiten.bind(Logos.cache_path(art)))
			set_process(true)
		else:
			var l := Logos.loader()
			if l:
				if not l.is_connected("logo_ready", _bereit):
					l.connect("logo_ready", _bereit)
				l.call_deferred("fetch", art)

	## Logo aus dem Cache lesen und einfarbig machen (im Hintergrund). null, wenn die Datei nichts taugt.
	static func _vorbereiten(pfad: String) -> Image:
		var img := Logos.prepare(Logos.load_image(pfad))
		return Logos.mono(nur_zeichen(img)) if img else null

	## Nur das Zeichen links eines Logos mit Schriftzug (Discord: Zeichen + „Discord“): die Spalten bis zur
	## ersten deutlichen Lücke. Logos ohne Lücke oder ohne Schriftzug (fast quadratisch) bleiben, wie sie sind.
	static func nur_zeichen(img: Image) -> Image:
		var w := img.get_width()
		var h := img.get_height()
		if w < int(h * 1.6) or h <= 0:
			return img
		var schritt := maxi(1, h / 48)
		var luecke := maxi(2, h / 12)
		var start := -1
		var leer := 0
		for x in w:
			var voll := false
			for y in range(0, h, schritt):
				if img.get_pixel(x, y).a > 0.2:
					voll = true
					break
			if voll:
				if start < 0:
					start = x
				leer = 0
			elif start >= 0:
				leer += 1
				if leer >= luecke:
					var ende := x - leer + 1
					return img.get_region(Rect2i(start, 0, ende - start, h)) if ende - start >= h / 3 else img
		return img

	func _bereit(key: String) -> void:
		if key == art and is_inside_tree():
			_zeigen()

	func _process(_dt: float) -> void:
		var lauf: Arbeit.Auftrag = _arbeit.get(art)
		if lauf and not lauf.fertig:
			return
		if lauf and not _fertig.has(art):
			var img := lauf.wert as Image
			lauf.wert = null
			if img and not img.is_empty():
				_fertig[art] = ImageTexture.create_from_image(img)
		_zeigen()
		set_process(false)


class _Pill extends Control:
	var text := ""
	var kind := "line"
	var host: Control

	func setup(t: String, k: String, h: Control) -> Control:
		text = t
		kind = k
		host = h
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var f := UzTheme.font("bold")
		var w := f.get_string_size(tr(text).to_upper() if kind == "line" else text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		custom_minimum_size = Vector2(maxf(26.0, w + 18.0), 26)
		return self

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var t := tr(text).to_upper() if kind == "line" else text
		var ink := UzTheme.col("accent")
		if kind == "fill":
			draw_rect(r, ink)
			ink = UzTheme.col("on_accent")
		else:
			draw_rect(r.grow(-0.5), ink, false, 1.0)
		var f := UzTheme.font("bold")
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(f, Vector2((size.x - tw) * 0.5, (size.y + f.get_ascent(15) - f.get_descent(15)) * 0.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ink)

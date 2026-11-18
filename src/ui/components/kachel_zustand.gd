extends Control
## Zustandsschicht einer lebendigen Kachel (Roadmap 101 → 124): ein kleines Abzeichen auf dem
## Cover – Freunde spielen gerade, Update, Patch heute, Rabatt, neue Erfolge, Server gestört.
## Welcher Zustand gilt, entscheidet src/core/kacheln.gd (höchstens einer, feste Rangfolge).
##
## Liegt als eigenes Kind in der Bildmaske des Covers (cover_card.gd setzt sie nur ein) – über dem
## Bild, unter den Plaketten. Mit Bild steht das Abzeichen unten links auf einem weichen Verlauf,
## ohne Bild oben links (unten steht dort der Titel des Ersatz-Covers).
##
## Aufwachen: Ruht die Auswahl kurz auf der Kachel, öffnet sich das Abzeichen nach oben und zeigt
## eine zweite Zeile (wer spielt, wie der Patch heißt …). Das Bild selbst steht still (Wunsch:
## nichts zoomt von allein; die Auswahl zeigt allein der Cursor). Beim Blättern passiert nichts
## (erst nach WAKE_S). Leichter Modus: nur das ruhende Abzeichen.

const U := preload("res://src/ui/u.gd")
const Leicht := preload("res://src/core/leicht.gd")
const Kacheln := preload("res://src/core/kacheln.gd")
const Avatar := preload("res://src/ui/components/avatar.gd")

const PAD := 10.0           ## Abstand zum Rand des Covers
const PAD_B := 12.0         ## unten etwas mehr (darunter liegt der Erfolgsbalken)
const IN_X := 10.0          ## Innenabstand des Abzeichens
const IN_Y := 5.0
const GAP := 2.0            ## zwischen erster und zweiter Zeile
const AV := 22              ## Profilbilder im Abzeichen
const AV_STEP := 15.0       ## so weit liegen sie übereinander
const WAKE_S := 0.75        ## so lange muss die Auswahl ruhen, bis die Kachel aufwacht
const BAR_H := 4.0
## Das Abzeichen liegt auf einem Bild: immer dunkles Glas mit heller Schrift, auch im hellen
## Farbschema (sonst wäre es auf dem dunklen Verlauf darunter ein greller Fleck).
const GLASS := Color(0.035, 0.038, 0.045, 0.82)
const INK := Color(0.953, 0.945, 0.925)

var card: Control           ## das Cover (cover_card.gd)
var img: TextureRect        ## sein Bild (_has_art: liegt eins da?)
var state: Dictionary = {}
var _sig := ""
var _pill: Control
var _row: HBoxContainer
var _l1: Label
var _l2: Label
var _t := 0.0               ## 0 ruhend … 1 wach (zweite Zeile ganz offen)
var _focus := false
var _wake_gen := 0
var _tw: Tween
var _due := false
var _stale := false         ## eine Meldung kam, während die Karte weit weg lag (großes Raster)


func setup(c: Control, image: TextureRect) -> Control:
	card = c
	img = image
	return self


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.full_rect(self)
	resized.connect(_place)
	if img:
		img.visibility_changed.connect(_on_img)
	Social.updated.connect(_on_any)
	Installs.changed.connect(_on_install)
	Installs.queue_changed.connect(_queue)
	Store.updated.connect(_queue)
	Achievements.updated.connect(_on_any)
	DiscordChat.changed.connect(_queue)
	Config.changed.connect(_on_config)
	refresh()


func _on_any(_what: Variant = null) -> void:
	_queue()


func _on_install(id: String) -> void:
	if card and id == str(card.game.get("id", "")):
		_queue()


func _on_config(k: String) -> void:
	if k == "system.live_tiles":
		_queue()


func _on_img() -> void:
	if _stale:
		_queue()
	_place()


## Viele Meldungen kurz hintereinander (Freunde, Shop, Erfolge) nur einmal umsetzen. Karten eines
## großen Rasters, die ihr Bild gerade abgegeben haben (weit weg), rechnen erst beim Wiederkommen.
func _queue() -> void:
	if card and bool(card.get("lazy")) and not card.image_requested():
		_stale = true
		return
	_stale = false
	if _due:
		return
	_due = true
	refresh.call_deferred()


## Zustand neu bestimmen; nur bei einem anderen Zustand wird das Abzeichen neu gebaut.
func refresh() -> void:
	_due = false
	if not is_inside_tree() or card == null:
		return
	var s: Dictionary = {}
	# Auswahlmodus, oder Uzai installiert das Spiel gerade (dann zeigt das Cover den Download).
	var parent := get_parent()
	if int(card.get("checked")) < 0 and not (parent and parent.has_node("InstallBadge")):
		s = Kacheln.for_game(card.game)
	var sig := "%s|%s|%s|%d" % [s.get("kind", ""), s.get("text", ""), s.get("more", ""), (s.get("people", []) as Array).size()]
	if sig == _sig:
		if not s.is_empty() and float(s.get("frac", -1.0)) != float(state.get("frac", -1.0)):
			state = s
			queue_redraw()
		return
	var had := not state.is_empty()
	_sig = sig
	state = s
	_build()
	# Ein neuer Zustand blendet weich ein (beim ersten Aufbau steht er sofort da).
	if had and is_instance_valid(_pill) and is_visible_in_tree():
		_pill.modulate.a = 0.0
		create_tween().tween_property(_pill, "modulate:a", 1.0, U.T_BASE)


func _build() -> void:
	if is_instance_valid(_pill):
		_pill.queue_free()
	_pill = null
	queue_redraw()
	if state.is_empty():
		return
	_pill = _Pill.new()
	_pill.clip_contents = true
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.set("tint", str(state.get("kind", "")) in ["gestoert"])
	add_child(_pill)
	_row = U.hbox(7)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_child(_row)
	var people: Array = state.get("people", [])
	if not people.is_empty():
		_row.add_child(_Faces.new().setup(people))
	else:
		var ic := U.icon(str(state.get("icon", "info")), 16, str(state.get("color", "text")))
		if str(state.get("color", "text")) == "text":
			ic.modulate = INK
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_row.add_child(ic)
	_l1 = U.label(str(state.get("text", "")), "cap", "text", "ui_bold")
	_l1.add_theme_color_override("font_color", UzTheme.col(str(state.color)) if str(state.get("kind", "")) in ["rabatt", "gestoert"] else INK)
	_l1.clip_text = false
	_l1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_l1)
	# Zweite Zeile: höchstens zwei Zeilen, dann Auslassungszeichen (lange Patch-Titel).
	_l2 = U.label(str(state.get("more", "")), "cap", "muted", "medium", true)
	_l2.add_theme_color_override("font_color", Color(INK, 0.68))
	_l2.max_lines_visible = 2
	_l2.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_l2.modulate.a = 0.0
	# Namen von Freunden und Titel von Neuigkeiten nie übersetzen.
	if str(state.get("kind", "")) in ["freunde", "patch", "news", "rabatt"]:
		_l2.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_pill.add_child(_l2)
	_place.call_deferred()


## Größe und Lage des Abzeichens für den Wachheitsgrad _t.
func _place() -> void:
	if not is_instance_valid(_pill) or size.x <= 0.0:
		queue_redraw()
		return
	var art := _has_art()
	var max_w := size.x - PAD * 2.0
	if not art:
		# Oben rechts stehen dann Stern und Download-Zeichen: frei lassen.
		var fav: Variant = card.get("_fav")
		max_w -= (36.0 if fav is Control and is_instance_valid(fav) else 0.0) + (36.0 if not Library.is_installed(card.game) else 0.0)
	var r1 := _row.get_combined_minimum_size()
	var w0 := minf(r1.x + IN_X * 2.0, max_w)
	var h0 := r1.y + IN_Y * 2.0
	var has_more := _l2.text != ""
	# Gemessen wird der Text, der auch dasteht (atr): Namen und Titel unübersetzt, siehe oben.
	var l2w := _l2.get_theme_font("font").get_string_size(_l2.atr(_l2.text), HORIZONTAL_ALIGNMENT_LEFT, -1, _l2.get_theme_font_size("font_size")).x if has_more else 0.0
	var w1 := clampf(maxf(r1.x, l2w) + IN_X * 2.0, w0, max_w)
	# Passt die zweite Zeile nicht in die Breite, bekommt sie zwei Zeilen.
	var lines := 2.0 if l2w > w1 - IN_X * 2.0 + 0.5 else 1.0
	var l2h := ceilf(lines * _l2.get_line_height() + (lines - 1.0) * _l2.get_theme_constant("line_spacing")) + 1.0 if has_more else 0.0
	var h1 := h0 + (l2h + GAP if has_more else 0.0)
	var k := _ease(_t)
	var w := lerpf(w0, w1, k)
	var h := lerpf(h0, h1, k)
	_row.position = Vector2(IN_X, IN_Y)
	_row.size = Vector2(minf(r1.x, max_w - IN_X * 2.0), r1.y)
	_l2.position = Vector2(IN_X, IN_Y + r1.y + GAP)
	_l2.size = Vector2(w1 - IN_X * 2.0, l2h)
	_l2.modulate.a = clampf((_t - 0.35) / 0.65, 0.0, 1.0)
	var y := size.y - PAD_B - h if art else _top()
	_pill.position = Vector2(PAD, y).round()
	_pill.size = Vector2(w, h).round()
	_pill.queue_redraw()
	queue_redraw()


static func _ease(v: float) -> float:
	return 1.0 - pow(1.0 - clampf(v, 0.0, 1.0), 3.0)


func _has_art() -> bool:
	return img != null and img.visible and img.texture != null


## Ohne Bild: oben links, unter dem Schild, das dort schon steht (System).
func _top() -> float:
	var y := PAD
	var parent := get_parent()
	for n in ["SysTag"]:
		var t: Control = parent.get_node_or_null(n) if parent else null
		if t and t.visible:
			y = maxf(y, t.position.y + t.size.y + 6.0)
	return y


## Mit Bild: weicher Verlauf unten, damit das Abzeichen auf jedem Bild lesbar ist; dazu der
## Fortschritt eines laufenden Updates als Balken ganz unten.
func _draw() -> void:
	if state.is_empty():
		return
	if _has_art() and is_instance_valid(_pill):
		var top := _pill.position.y - 46.0
		var r := Rect2(0, top, size.x, size.y - top)
		draw_texture_rect(U.fade_texture(true, true), r, false, Color(0, 0, 0, 0.5 + 0.18 * _ease(_t)))
	var frac := float(state.get("frac", -1.0))
	if frac >= 0.0:
		var b := Rect2(0, size.y - BAR_H, size.x, BAR_H)
		draw_rect(b, Color(0.05, 0.05, 0.06, 0.92))
		draw_rect(Rect2(b.position, Vector2(size.x * clampf(frac, 0.0, 1.0), BAR_H)), UzTheme.col("accent"))


# --- Aufwachen -------------------------------------------------------------------------------------

## Vom Cover: Auswahl kommt bzw. geht.
func focus(on: bool) -> void:
	_focus = on
	_wake_gen += 1
	if not on:
		_sleep()
		return
	if Leicht.active or not is_inside_tree():
		return
	var gen := _wake_gen
	get_tree().create_timer(WAKE_S).timeout.connect(func() -> void:
		if gen == _wake_gen and _focus and is_inside_tree():
			_wake()
	)


func _wake() -> void:
	if _tw:
		_tw.kill()
	if is_instance_valid(_pill) and _l2.text != "":
		_tw = create_tween()
		_tw.tween_method(_set_t, _t, 1.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Schlafen legen (Auswahl weg, Leichter Modus, Übergänge anderer Teile): schnell und ruhig zurück.
func sleep() -> void:
	_wake_gen += 1
	_focus = false
	_sleep()


func _sleep() -> void:
	if _tw:
		_tw.kill()
	if _t > 0.0:
		_tw = create_tween()
		_tw.tween_method(_set_t, _t, 0.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_t(v: float) -> void:
	_t = v
	_place()


## Ist die Kachel gerade wach (für Proben und Tests)?
func awake() -> bool:
	return _t > 0.99


# --- Bausteine -------------------------------------------------------------------------------------

## Grund des Abzeichens: dunkles Glas mit feiner Kante; „gestört“ leicht rot getönt.
class _Pill extends Control:
	var tint := false
	var _sb: StyleBoxFlat

	func _draw() -> void:
		if _sb == null:
			_sb = StyleBoxFlat.new()
			_sb.anti_aliasing = true
			_sb.set_border_width_all(1)
		var bg := GLASS
		if tint:
			bg = bg.lerp(UzTheme.col("danger"), 0.28)
		_sb.bg_color = bg
		_sb.border_color = Color(INK, 0.1)
		_sb.set_corner_radius_all(int(minf(UzTheme.r_round(14), size.y * 0.5)))
		draw_style_box(_sb, Rect2(Vector2.ZERO, size))


## Bis zu drei Gesichter übereinander, jedes mit einem dunklen Rand zum nächsten.
class _Faces extends Control:
	var _n := 0

	func setup(people: Array) -> Control:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_n = people.size()
		for i in _n:
			var p: Dictionary = people[i]
			var a = Avatar.new().setup(str(p.get("name", "")), str(p.get("avatar", "")), "", AV)
			a.position = Vector2(i * AV_STEP, 0)
			add_child(a)
		custom_minimum_size = Vector2(AV + AV_STEP * (_n - 1), AV)
		return self

	func _draw() -> void:
		for i in range(1, _n):
			draw_circle(Vector2(i * AV_STEP + AV * 0.5, AV * 0.5), AV * 0.5 + 1.5, Color(GLASS, 0.95))

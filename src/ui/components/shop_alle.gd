extends Control
## Die letzte Kachel einer Reihe im Shop: „Alle anzeigen“ – eine ruhige matte Fläche in der Form
## der Karten mit einem Pfeil in einer runden Scheibe, darunter der Name und die Anzahl. A öffnet
## die ganze Liste als Ort (B führt zurück auf diese Kachel). Gewählt hebt sie sich wie eine Karte
## und trägt den Kachel-Cursor der Marke.

signal chosen

const U := preload("res://src/ui/u.gd")
const ShopCard := preload("res://src/ui/components/shop_card.gd")

var count := 0
var card_w := 228.0


func setup(n: int, w := 228.0) -> Control:
	count = n
	card_w = w
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(card_w, ShopCard.height_for(card_w, true))
	set_meta("uz_hint_a", "Alle anzeigen")
	focus_entered.connect(func() -> void: U.focus_anim(self, true))
	focus_exited.connect(func() -> void: U.focus_anim(self, false))
	gui_input.connect(func(e: InputEvent) -> void:
		Nav.klick(self, e)
	)


func activate() -> void:
	chosen.emit()


func _draw() -> void:
	var f := float(get_meta("uz_f", 0.0)) if has_meta("uz_f") else 0.0
	var lift := -10.0 * f
	var ih := roundf(card_w * 1.5)
	var rc := UzTheme.r_cover()
	var r := Rect2(Vector2(0, lift), Vector2(card_w, ih))
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0, 0, 0, 0)
	sh.set_corner_radius_all(rc)
	sh.shadow_color = Color(0, 0, 0, UzTheme.shadow_alpha(0.3 + 0.2 * f))
	sh.shadow_size = int(14 + 14 * f)
	sh.shadow_offset = Vector2(0, 10)
	draw_style_box(sh, Rect2(Vector2(4, lift + 6), Vector2(card_w - 8, ih - 8)))
	draw_style_box(UzTheme.box(UzTheme.col("surface_hi").lerp(UzTheme.col("text"), 0.03 * f), rc), r)
	# Runde Scheibe mit Pfeil in der Mitte; gewählt eine Spur heller.
	var c := r.get_center()
	draw_circle(c, 38.0, UzTheme.col("text", 0.08 + 0.06 * f))
	var ic := Icons.tex("chevron_right", 36)
	draw_texture_rect(ic, Rect2(c - Vector2(17, 18), Vector2(36, 36)), false, UzTheme.col("text", 0.9))
	UzTheme.draw_tile_focus(self, r, rc, minf(f, 1.0))
	var bold := UzTheme.font("bold")
	var med := UzTheme.font("medium")
	var y := ih + 30
	draw_string(bold, Vector2(2, y), tr("Alle anzeigen"), HORIZONTAL_ALIGNMENT_LEFT, card_w - 4, 18, UzTheme.col("text"))
	if count > 0:
		draw_string(med, Vector2(2, y + 26), U.plural(count, "Spiel", "Spiele"), HORIZONTAL_ALIGNMENT_LEFT, card_w - 4, 15, UzTheme.col("muted"))

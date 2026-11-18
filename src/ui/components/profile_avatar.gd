extends Control
## Profilbild eines Uzai-Profils (Roadmap 109): runde Fläche in der Farbe des Profils mit weichem
## Glanz, darauf der Anfangsbuchstabe oder ein Zeichen aus Uzais Symbolsatz. Optional ein kleines
## Schloss (PIN) unten rechts. Ohne Bilder aus dem Netz – sieht auf jedem PC gleich aus.

const U := preload("res://src/ui/u.gd")
const Profiles := preload("res://src/core/profiles.gd")

var profile: Dictionary = {}
var px := 96
var lock := false                ## Schloss-Abzeichen, wenn das Profil eine PIN hat


func setup(p: Dictionary, size_px := 96, show_lock := false) -> Control:
	profile = p
	px = size_px
	lock = show_lock and p.has("pin")
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self


## Profil nachträglich ändern (Bearbeiten): zeichnet sofort neu.
func set_profile(p: Dictionary) -> void:
	profile = p
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(px, px)


func _draw() -> void:
	var c := Vector2(px, px) * 0.5
	var r := px * 0.5
	var base := Profiles.color_of(profile)
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 64:
		var a := TAU * i / 64.0
		var p := Vector2(cos(a), sin(a))
		pts.append(c + p * r)
		uvs.append(Vector2(0.5, 0.5) + p * 0.5)
	# Fläche etwas dunkler als die Farbe, oben ein weicher Glanz, unten ein Hauch Tiefe.
	draw_colored_polygon(pts, base.darkened(0.18))
	draw_colored_polygon(pts, Color(1, 1, 1, 0.18), uvs, U.fade_texture(true))
	draw_arc(c, r - 0.75, 0.0, TAU, 96, Color(1, 1, 1, 0.08), 1.5, true)
	var ink := Color(1, 1, 1, 0.95) if base.get_luminance() < 0.62 else Color(0.08, 0.07, 0.06, 0.9)
	var av := str(profile.get("avatar", "buchstabe"))
	if av == "buchstabe" or av == "":
		var f := UzTheme.display("bold")
		var fs := int(px * 0.44)
		var ch := str(profile.get("name", "?")).strip_edges().substr(0, 1).to_upper()
		if ch == "":
			ch = "?"
		# Eigener Name: nie übersetzen (kein tr()).
		var sz := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, Vector2(c.x - sz.x * 0.5, c.y - sz.y * 0.5 + f.get_ascent(fs)), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	else:
		var ip := int(px * 0.5)
		draw_texture_rect(Icons.tex(av, ip), Rect2(c - Vector2(ip, ip) * 0.5, Vector2(ip, ip)), false, ink)
	if lock:
		var lr := maxf(13.0, px * 0.15)
		var lc := Vector2(px, px) * 0.86
		draw_circle(lc, lr + 3.0, UzTheme.col("bg"), true, -1.0, true)
		draw_circle(lc, lr, UzTheme.col("surface_hi"), true, -1.0, true)
		var lp := int(lr * 1.2)
		draw_texture_rect(Icons.tex("lock", lp), Rect2(lc - Vector2(lp, lp) * 0.5, Vector2(lp, lp)), false, UzTheme.col("text"))

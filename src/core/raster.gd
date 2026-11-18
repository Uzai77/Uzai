extends RefCounted
## The grid the UI moves on. Menus have to feel smooth at any resolution and refresh rate, including 4K at 120 Hz.
##
## Godot snaps 2D transforms to UI points (project.godot: snap_2d_transforms_to_pixel), not to physical screen
## pixels (verified: an offset of half a point had no effect at 2× scale). Uzai is built for 1920 × 1080 points;
## on a 4K TV one point is 2 × 2 pixels. Every movement there ran on the 1080p grid, and the ease-out of a
## movement, which advances at least one point per frame (sized for 60 Hz), stuttered again at 120 Hz:
## step, pause, step.
##
## From SCHWELLE pixels per point upward, Uzai therefore stops snapping to points. Whatever containers place sits
## on whole points anyway (gui/common/snap_controls_to_pixels), and so on whole pixels at 2× scale: static text
## stays as sharp as before; only movement becomes twice as fine.
## schritt: smallest visible step in points – 1 with snapping, otherwise one pixel (0.5 at 4K).
## Nav calls pruefen() every frame (one query): the UI size, the screen and the window can change it.

const SCHWELLE := 1.5

static var schritt := 1.0
static var skala := 1.0


## Skala des Fensters lesen und das Einrasten danach stellen. Ändert nur, wenn sich etwas geändert hat.
static func pruefen(root: Window) -> void:
	if root == null:
		return
	var s := root.get_stretch_transform().x.x
	if not (s > 0.01) or is_equal_approx(s, skala) and root.snap_2d_transforms_to_pixel == (s < SCHWELLE):
		return
	setzen(root, s)


static func setzen(root: Window, s: float) -> void:
	skala = maxf(s, 0.01)
	var rasten := skala < SCHWELLE
	if root:
		root.snap_2d_transforms_to_pixel = rasten
	schritt = 1.0 if rasten else 1.0 / skala


## v auf das Raster gerundet (ganze Punkte bzw. ganze Bildpunkte).
static func rund(v: float) -> float:
	return roundf(v / schritt) * schritt

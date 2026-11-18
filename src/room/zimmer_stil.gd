extends RefCounted
## Die eigene Bedien-Optik des Zimmers (Modus-Leiste, Kategorienleiste, Katalog-Raster, Kontextmenü
## am Objekt): warm wie das Zimmer selbst, aber ruhig – matte, fast deckende Flächen in dunklem
## Walnuss statt Graphit, eine warme Haarlinie, Tinte in Elfenbein. Die Marke gilt weiter: eckig
## (Radius 2), ein Akzent (der Strich unter dem Gewählten), derselbe Cursor wie überall
## (UzTheme.draw_selection, draw_tile_focus), kein Glas. Bewusst nicht die Listen-Optik der
## Einstellungen: Kacheln, Leisten und kurze Listen direkt am Ding.

const FLAECHE := Color(0.105, 0.088, 0.074, 0.93)       ## Leisten und Tafeln
const FLAECHE_HOCH := Color(0.15, 0.126, 0.106, 0.97)   ## Kacheln, gewähltes Segment
const KACHEL := Color(0.19, 0.16, 0.135, 1.0)           ## Grund unter einem Möbelbild
const LINIE := Color(0.96, 0.88, 0.76, 0.14)            ## warme Haarlinie
const TINTE := Color(0.957, 0.93, 0.894, 1.0)            ## Schrift
const LEISE := Color(0.74, 0.69, 0.62, 1.0)              ## leise Schrift
const RADIUS := 2


## Eine matte Fläche mit Haarlinie und weichem Schatten darunter (Höhenstufe „schwebt“, leise).
static func flaeche(ci: CanvasItem, r: Rect2, a: float, farbe := FLAECHE, schatten := true) -> void:
	if a <= 0.01:
		return
	if schatten:
		for i in 3:
			var g := 4.0 + i * 5.0
			ci.draw_rect(Rect2(r.position + Vector2(-g * 0.5, g * 0.6), r.size + Vector2(g, g * 0.2)), Color(0, 0, 0, 0.07 * a))
	ci.draw_rect(r, Color(farbe, farbe.a * a))
	ci.draw_rect(r, Color(LINIE, LINIE.a * a), false, 1.0)


## Text mit einem Hauch Schatten (trägt auch über hellen Wänden).
static func text(ci: CanvasItem, f: Font, p: Vector2, t: String, fs: int, c: Color, breite := -1.0) -> void:
	ci.draw_string(f, p + Vector2(0, 1.5), t, HORIZONTAL_ALIGNMENT_LEFT, breite, fs, Color(0, 0, 0, 0.35 * c.a))
	ci.draw_string(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, breite, fs, c)

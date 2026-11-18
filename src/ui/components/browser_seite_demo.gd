extends Control
## Uzai-Browser im Vorführmodus: zeichnet die Platzhalter-Seite (browser_demo.gd) dort, wo unter
## Windows das Fenster des Wirts mit der echten Seite liegt – hell wie eine gewöhnliche Webseite, damit
## man sieht, was von der Seite kommt und was Uzai darüber zeichnet. Nur Vorführung und Proben.

const P := preload("res://src/core/browser_protokoll.gd")

var seite := {}

const HELL := Color("#f5f5f7")
const TINTE := Color("#1d1d22")
const LEISE := Color("#6b6b75")
const LINIE := Color("#e2e2e8")
const LINK := Color("#2a55c8")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func zeigen(s: Dictionary) -> void:
	seite = s
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), HELL)
	if seite.is_empty():
		return
	var ansicht: Vector2 = seite.ansicht
	var k := size.x / maxf(ansicht.x, 1.0)
	var sy := float(seite.sy)
	var f := UzTheme.font("regular")
	var fb := UzTheme.font("bold")
	for b in seite.bloecke:
		var r: Rect2 = b.r
		var sr := Rect2((r.position - Vector2(0, sy)) * k, r.size * k)
		if sr.end.y < 0 or sr.position.y > size.y:
			continue
		var art := int(b.art)
		var bild := str(b.get("art_bild", ""))
		var text := str(b.text)
		if bild == "leiste":
			draw_rect(sr, Color("#ffffff"))
			draw_rect(Rect2(sr.position.x, sr.end.y - 1, sr.size.x, 1), LINIE)
		elif bild == "fuss":
			draw_rect(sr, Color("#e9e9ee"))
		elif bild == "logo":
			draw_string(fb, sr.position + Vector2(0, sr.size.y * 0.72), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(26 * k), TINTE)
		elif bild == "ueberschrift":
			draw_string(fb, sr.position + Vector2(0, sr.size.y * 0.8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(26 * k), TINTE)
		elif bild == "titel":
			draw_string(fb, sr.position + Vector2(0, sr.size.y * 0.8), text, HORIZONTAL_ALIGNMENT_LEFT, sr.size.x, int(36 * k), TINTE)
		elif bild == "text":
			var n := int(b.get("zeilen", 4))
			for i in n:
				var y := sr.position.y + i * 30.0 * k
				if y > sr.end.y:
					break
				var w := sr.size.x * (0.62 if i % 5 == 4 else (0.92 - float((i * 37) % 9) * 0.03))
				draw_rect(Rect2(sr.position.x, y + 8 * k, w, 12 * k), Color("#d9d9e0"))
		elif art == P.ARTEN.find("bild"):
			var hue := float(b.get("farbe", 0.5))
			var c1 := Color.from_hsv(hue, 0.35, 0.78)
			var c2 := Color.from_hsv(fmod(hue + 0.08, 1.0), 0.45, 0.55)
			var bild_r := Rect2(sr.position, Vector2(sr.size.x, sr.size.y - (48 * k if sr.size.y > 200 * k else 0.0)))
			_verlauf(bild_r, c1, c2)
			var ty := bild_r.end.y + 32 * k if bild_r.size.y < sr.size.y else bild_r.end.y - 24 * k
			var tc := TINTE if bild_r.size.y < sr.size.y else Color.WHITE
			draw_string(fb, Vector2(sr.position.x + (0.0 if bild_r.size.y < sr.size.y else 24 * k), ty), text, HORIZONTAL_ALIGNMENT_LEFT,
					sr.size.x - 32 * k, int((22 if sr.size.x < 500 * k else 34) * k), tc)
		elif art == P.ARTEN.find("video"):
			draw_rect(sr, Color("#101014"))
			var c := sr.get_center()
			var spielt := bool(seite.get("video", false))
			if spielt:
				draw_rect(Rect2(c - Vector2(22, 26) * k, Vector2(14, 52) * k), Color(1, 1, 1, 0.85))
				draw_rect(Rect2(c + Vector2(8, -26) * k, Vector2(14, 52) * k), Color(1, 1, 1, 0.85))
			else:
				draw_colored_polygon(PackedVector2Array([c + Vector2(-20, -30) * k, c + Vector2(-20, 30) * k, c + Vector2(30, 0) * k]),
						Color(1, 1, 1, 0.85))
			draw_rect(Rect2(sr.position.x, sr.end.y - 6 * k, sr.size.x * 0.32, 6 * k), Color("#e53935"))
		elif art == P.ARTEN.find("feld"):
			draw_rect(sr, Color.WHITE)
			draw_rect(sr, Color("#c7c7d0"), false, maxf(1.0, k))
			var wert := str((seite.felder as Dictionary).get(int(b.id), ""))
			draw_string(f, sr.position + Vector2(14 * k, sr.size.y * 0.66), wert if wert != "" else text, HORIZONTAL_ALIGNMENT_LEFT,
					sr.size.x - 20 * k, int(18 * k), TINTE if wert != "" else LEISE)
		elif art == P.ARTEN.find("knopf"):
			draw_rect(sr, Color("#2a55c8"))
			var w2 := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * k)).x
			draw_string(fb, Vector2(sr.get_center().x - w2 * 0.5, sr.position.y + sr.size.y * 0.66), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(18 * k),
					Color.WHITE)
		elif art == P.ARTEN.find("link"):
			var gross := sr.size.y > 80 * k
			if gross:
				draw_rect(Rect2(sr.position.x, sr.end.y - 1, sr.size.x, 1), LINIE)
				draw_string(fb, sr.position + Vector2(0, 34 * k), text, HORIZONTAL_ALIGNMENT_LEFT, sr.size.x, int(22 * k), TINTE)
				draw_rect(Rect2(sr.position.x, sr.position.y + 52 * k, sr.size.x * 0.8, 10 * k), Color("#d9d9e0"))
			else:
				var farbe := LINK if int(b.bereich) in [P.BEREICHE.find("inhalt"), P.BEREICHE.find("seite")] else TINTE
				draw_string(f, sr.position + Vector2(10 * k, sr.size.y * 0.66), text, HORIZONTAL_ALIGNMENT_LEFT, sr.size.x, int(18 * k), farbe)


func _verlauf(r: Rect2, a: Color, b: Color) -> void:
	var n := 12
	for i in n:
		var t := float(i) / n
		draw_rect(Rect2(r.position.x, r.position.y + r.size.y * t, r.size.x, r.size.y / n + 1), a.lerp(b, t))

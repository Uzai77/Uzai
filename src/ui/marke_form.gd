extends RefCounted
## Die Formen der Marke „U-Band“ (docs/DESIGN.md): das Zeichen – ein U, der Länge nach in ein
## äußeres und ein inneres Band geteilt, dazwischen eine Fuge aus Licht durch den ganzen Bogen – und
## die Wortmarke UZAI aus eigenen Buchstaben (U wie das Zeichen, Z mit einer Lichtlinie in der
## Diagonale, A als Λ mit einem Querstrich aus Licht, I).
## Hier stehen nur Umrisse und Linien: uzai_logo.gd zeichnet das Zeichen daraus flach, boot.gd die
## Startanimation, tools/marke_rendern.gd schreibt icon.svg.
## Alle Formen im Maß des Zeichens: Höhe 1,9, Breite 1,7, Mitte im Ursprung.

const H := 1.9
const B := 1.7
const STRICH := 0.5
const FUGE := 0.07
## Wortmarke: Versalhöhe 1, Strich WS.
const WS := 0.22


## Umrisse der Buchstaben U, Z, A, I (je eine Liste von Vielecken, Koordinaten des Buchstabens:
## linke untere Ecke im Ursprung, Versalhöhe 1). U der Länge nach geteilt wie das Zeichen, Z aus
## einem Stück, A als Λ (der Querstrich ist Licht), I.
static func wort_umrisse() -> Array:
	var linien := wort_linien()
	var u := teilen(_schieben(u_glyph(1.0, W_U, WS), Vector2(W_U * 0.5, 0.5)), [_lang(linien[0], 0.5)], 0.04)
	var z := [_schieben(z_glyph(1.0, W_Z, WS), Vector2(W_Z * 0.5, 0.5))]
	var aus := PackedVector2Array([Vector2(0, 0), Vector2(W_A, 0), Vector2(W_A * 0.5, 1.0)])
	var inn: PackedVector2Array = (Geometry2D.offset_polygon(aus, -WS) as Array)[0]
	var by := 1e9
	for q in inn:
		by = minf(by, q.y)
	var bx0 := 1e9
	var bx1 := -1e9
	for q in inn:
		if absf(q.y - by) < 0.02:
			bx0 = minf(bx0, q.x)
			bx1 = maxf(bx1, q.x)
	var unter := PackedVector2Array([Vector2(bx0, by + 0.01), Vector2(bx1, by + 0.01), Vector2(bx1 + 0.3, -1), Vector2(bx0 - 0.3, -1)])
	var kerbe: PackedVector2Array = (Geometry2D.merge_polygons(inn, unter) as Array)[0]
	var a := Geometry2D.clip_polygons(aus, kerbe)
	var i := [PackedVector2Array([Vector2(0, 0), Vector2(WS, 0), Vector2(WS, 1), Vector2(0, 1)])]
	return [u, z, a, i]


## Breiten der Buchstaben der Wortmarke und der Abstand dazwischen.
const W_U := 0.8
const W_Z := 0.78
const W_A := 0.86
const W_LUFT := 0.2


## Linke Kante von U, Z, A, I und die ganze Breite der Wortmarke.
static func wort_x() -> Array:
	var xu := 0.0
	var xz := xu + W_U + W_LUFT
	var xa := xz + W_Z + W_LUFT
	var xi := xa + W_A + W_LUFT
	return [xu, xz, xa, xi, xi + WS]


## Die Lichter der Wortmarke als Linien in der Reihenfolge, in der das Licht sie schreibt (je in
## den Koordinaten des Buchstabens, linke untere Ecke im Ursprung): die Fuge im U (von oben links
## durch den Bogen), die Diagonale im Z (von oben rechts nach unten links), der Querstrich im A.
static func wort_linien() -> Array:
	var u := _schieben(u_linie(W_U * 0.5 - WS * 0.5, -0.5 + W_U * 0.5, 0.498), Vector2(W_U * 0.5, 0.5))
	var dw := WS * 1.4
	var a0 := Vector2(W_Z * 0.5 - dw * 0.5, 0.5 - WS) + Vector2(W_Z * 0.5, 0.5)
	var a1 := Vector2(-W_Z * 0.5 + dw * 0.5, -0.5 + WS) + Vector2(W_Z * 0.5, 0.5)
	var dir := (a1 - a0).normalized()
	var z := PackedVector2Array([a0 - dir * 0.02, a1 + dir * 0.02])
	var a := PackedVector2Array([Vector2(0.17, 0.34), Vector2(W_A - 0.17, 0.34)])
	return [u, z, a]


static func _schieben(p: PackedVector2Array, v: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in p:
		out.append(q + v)
	return out


## Eine Linie oben um d verlängert (erster und letzter Punkt), damit der Schnitt ganz durchgeht.
static func _lang(p: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := p.duplicate()
	out[0] += Vector2(0, d)
	out[out.size() - 1] += Vector2(0, d)
	return out


# --- Formen ---------------------------------------------------------------------------------

## Ein U der Höhe h und Breite w mit Strich s (Mitte im Ursprung): gerade Schenkel, unten ein Bogen.
static func u_glyph(h: float, w: float, s: float) -> PackedVector2Array:
	var t := h * 0.5
	var r := w * 0.5
	var cy := -t + r
	var out := PackedVector2Array([Vector2(-r, t), Vector2(-r, cy)])
	for i in range(1, 48):
		var a := PI + PI * i / 48.0
		out.append(Vector2(cos(a), sin(a)) * r + Vector2(0, cy))
	out.append_array(PackedVector2Array([Vector2(r, cy), Vector2(r, t), Vector2(r - s, t), Vector2(r - s, cy)]))
	for i in range(1, 48):
		var a := -PI * i / 48.0
		out.append(Vector2(cos(a), sin(a)) * (r - s) + Vector2(0, cy))
	out.append_array(PackedVector2Array([Vector2(-r + s, cy), Vector2(-r + s, t)]))
	return out


## Linie in Form eines U: Schenkel bei ±rx von oben (y = oben) bis cy, dazwischen ein Halbkreis.
static func u_linie(rx: float, cy: float, oben: float) -> PackedVector2Array:
	var out := PackedVector2Array([Vector2(-rx, oben), Vector2(-rx, cy)])
	for i in range(1, 48):
		var a := PI + PI * i / 48.0
		out.append(Vector2(cos(a), sin(a)) * rx + Vector2(0, cy))
	out.append_array(PackedVector2Array([Vector2(rx, cy), Vector2(rx, oben)]))
	return out


## Ein Z der Höhe h und Breite w mit Strich s (Mitte im Ursprung).
static func z_glyph(h: float, w: float, s: float) -> PackedVector2Array:
	var t := h * 0.5
	var oben := PackedVector2Array([Vector2(-w * 0.5, t - s), Vector2(w * 0.5, t - s), Vector2(w * 0.5, t), Vector2(-w * 0.5, t)])
	var unten := PackedVector2Array([Vector2(-w * 0.5, -t), Vector2(w * 0.5, -t), Vector2(w * 0.5, -t + s), Vector2(-w * 0.5, -t + s)])
	var dw := s * 1.4
	var dia := PackedVector2Array([Vector2(-w * 0.5, -t + s), Vector2(-w * 0.5 + dw, -t + s), Vector2(w * 0.5, t - s), Vector2(w * 0.5 - dw, t - s)])
	var z: PackedVector2Array = (Geometry2D.merge_polygons(oben, dia) as Array)[0]
	return (Geometry2D.merge_polygons(z, unten) as Array)[0]


## Fläche entlang von Linien (Fugen der Breite fuge) in Teile schneiden.
static func teilen(flaeche: PackedVector2Array, linien: Array, fuge: float) -> Array:
	var teile: Array = [flaeche]
	for l in linien:
		var band: Array = Geometry2D.offset_polyline(l, fuge * 0.5, Geometry2D.JOIN_MITER, Geometry2D.END_BUTT)
		var neu: Array = []
		for t in teile:
			var rest: Array = [t]
			for bp in band:
				var r2: Array = []
				for q in rest:
					r2.append_array(Geometry2D.clip_polygons(q, bp))
				rest = r2
			neu.append_array(rest)
		teile = neu
	return teile


static func _laenge(p: PackedVector2Array) -> float:
	var l := 0.0
	for i in p.size():
		l += p[i].distance_to(p[(i + 1) % p.size()])
	return l

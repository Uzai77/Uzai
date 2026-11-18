extends SceneTree
## Schreibt das Zeichen „U-Band“ als Vektor: icon.svg (App-Symbol: dunkle Kachel, U in zwei Bändern
## mit Verlauf, helle Lichtlinie) und assets/uzai_logo.svg (Zeichen und Wortmarke UZAI). Formen aus
## src/ui/marke_form.gd, Farben wie uzai_logo.gd (farben „marke“) zum Markenviolett. Das .ico baut
## tools/make_logo.py aus denselben Formen.
##
##   godot --headless --path . --script res://tools/marke_rendern.gd

const Form := preload("res://src/ui/marke_form.gd")
const VIOLETT := Color("#a47bff")


func _initialize() -> void:
	_svg()
	print("marke_rendern: fertig")
	quit()


## Eloxal (oben heller, unten tief), Licht der Fugen – abgestimmt auf VIOLETT.
func _svg() -> void:
	var elox := Color.from_hsv(VIOLETT.h, clampf(VIOLETT.s * 1.35 + 0.12, 0.0, 0.85), clampf(VIOLETT.v * 0.62, 0.25, 0.7))
	var hell := elox.lightened(0.28)
	var tief := elox.darkened(0.22)
	var licht := Color.from_hsv(VIOLETT.h, clampf(VIOLETT.s * 0.9, 0.0, 0.6), 1.0)
	var rx := Form.B * 0.5 - Form.STRICH * 0.5
	var cy := -Form.H * 0.5 + Form.B * 0.5
	var teile := Form.teilen(Form.u_glyph(Form.H, Form.B, Form.STRICH), [Form.u_linie(rx, cy, Form.H)], Form.FUGE)
	teile.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool: return Form._laenge(a) > Form._laenge(b))
	var fuge := Form.u_linie(rx, cy, Form.H * 0.5)
	# App-Symbol: dunkle Kachel, das U-Band 150 von 256 hoch.
	var k := 150.0 / Form.H
	var mitte := Vector2(128, 128)
	var icon := '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">\n'
	icon += '  <!-- Uzai: U-Band (src/ui/marke_form.gd, tools/marke_rendern.gd). -->\n'
	icon += '  <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#201d29"/><stop offset="1" stop-color="#0c0b10"/></linearGradient>'
	icon += '<linearGradient id="e" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3d3948"/><stop offset="0.5" stop-color="#3d3948" stop-opacity="0"/></linearGradient>'
	icon += '<linearGradient id="a" x1="0" y1="0" x2="0.35" y2="1"><stop offset="0" stop-color="#%s"/><stop offset="1" stop-color="#%s"/></linearGradient>' % [hell.to_html(false), tief.to_html(false)]
	icon += '<linearGradient id="i" x1="0" y1="0" x2="0.35" y2="1"><stop offset="0" stop-color="#%s"/><stop offset="1" stop-color="#%s"/></linearGradient></defs>\n' % [
		elox.to_html(false), tief.darkened(0.25).to_html(false)]
	icon += '  <rect x="8" y="8" width="240" height="240" rx="54" fill="url(#g)"/>\n'
	icon += '  <rect x="8.75" y="8.75" width="238.5" height="238.5" rx="53.25" fill="none" stroke="url(#e)" stroke-width="1.5"/>\n'
	icon += '  <path fill="url(#a)" d="%s"/>\n' % _pfad(teile[0], mitte, k)
	icon += '  <path fill="url(#i)" d="%s"/>\n' % _pfad(teile[1], mitte, k)
	icon += '  <path fill="none" stroke="#%s" stroke-width="%s" stroke-linecap="butt" stroke-linejoin="round" d="%s"/>\n' % [
		licht.to_html(false), _z(Form.FUGE * k * 0.8), _linie(fuge, mitte, k)]
	icon += '</svg>\n'
	_schreiben("res://icon.svg", icon)
	# Zeichen und Wortmarke: Name in Versalhöhe 0,42 des Zeichens, rechts daneben, unten bündig.
	var breite := float(Form.wort_x()[4])
	var kz := 100.0 / Form.H
	var nh := 0.42 * Form.H * kz
	var z0 := Vector2(Form.B * 0.5 * kz, Form.H * 0.5 * kz)
	var wx := Form.B * kz + 0.5 * Form.H * kz
	var w := wx + breite * nh
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="-8 -8 %s %s">\n' % [roundi((w + 16) * 4), roundi((100 + 16) * 4), _z(w + 16), _z(116)]
	svg += '  <!-- Uzai: U-Band und Wortmarke UZAI, flach (src/ui/marke_form.gd, tools/marke_rendern.gd). -->\n'
	svg += '  <g fill="#%s"><path d="%s"/><path d="%s"/></g>\n' % [elox.lightened(0.12).to_html(false), _pfad(teile[0], z0, kz), _pfad(teile[1], z0, kz)]
	svg += '  <path fill="none" stroke="#%s" stroke-width="%s" d="%s"/>\n' % [licht.to_html(false), _z(Form.FUGE * kz * 0.8), _linie(fuge, z0, kz)]
	# Buchstaben: Umrisse aus demselben Bau (Grundlinie unten bündig mit dem Zeichen).
	var unten := Vector2(wx, 100.0)
	var umrisse := Form.wort_umrisse()
	var buchst := ""
	var lichter := ""
	var xs := Form.wort_x()
	var wl := Form.wort_linien()
	for i in 4:
		var bx := float(xs[i])
		for poly in (umrisse[i] as Array):
			buchst += '<path d="%s"/>' % _pfad_w(poly, unten + Vector2(bx * nh, 0), nh)
		if i < 3:
			lichter += '<path d="%s"/>' % _linie_w(wl[i], unten + Vector2(bx * nh, 0), nh)
	svg += '  <g fill="#%s">%s</g>\n' % [elox.lightened(0.12).to_html(false), buchst]
	svg += '  <g fill="none" stroke="#%s" stroke-width="%s">%s</g>\n' % [licht.to_html(false), _z(0.05 * nh), lichter]
	svg += '</svg>\n'
	_schreiben("res://assets/uzai_logo.svg", svg)


func _z(v: float) -> String:
	var t := "%.2f" % v
	while t.ends_with("0"):
		t = t.left(-1)
	return t.trim_suffix(".")


## Vieleck im Maß des Zeichens (y nach oben, Mitte im Ursprung) als SVG-Pfad um mitte, Maßstab k.
func _pfad(p: PackedVector2Array, mitte: Vector2, k: float) -> String:
	var t := ""
	for i in p.size():
		var q := mitte + Vector2(p[i].x, -p[i].y) * k
		t += ("M" if i == 0 else "L") + _z(q.x) + " " + _z(q.y) + " "
	return t + "Z"


func _linie(p: PackedVector2Array, mitte: Vector2, k: float) -> String:
	return _pfad(p, mitte, k).trim_suffix("Z").strip_edges()


## Wie _pfad, für Buchstaben (linke untere Ecke im Ursprung, Versalhöhe 1) ab der Grundlinie unten.
func _pfad_w(p: PackedVector2Array, unten: Vector2, k: float) -> String:
	return _pfad(p, unten, k)


func _linie_w(p: PackedVector2Array, unten: Vector2, k: float) -> String:
	return _linie(p, unten, k)


func _schreiben(res: String, text: String) -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path(res), FileAccess.WRITE)
	f.store_string(text)
	f.close()

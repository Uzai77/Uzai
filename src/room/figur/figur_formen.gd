extends RefCounted
## Formen für das Haustier und den Controller in der Hand der Figur (die Figur selbst ist ein
## Modell, figur_psx.gd) – alles hier erzeugt: Ellipsoide mit richtigen Normalen, Glieder
## (verjüngte Kapseln: Beine, Schwänze) und mehrere Teile in einem Netz (Herz) – das hält die Zahl der
## Zeichenaufrufe klein. Gleiche Formen werden nur einmal gebaut (Zwischenspeicher nach Maßen).
##
## Wie die Möbel (formen.gd) bekommen die Formen eine leichte Verdunklung nach unten in die
## Eckpunktfarbe – weiche Kontaktschatten ohne eigenen Rechenschritt.

const F := preload("res://src/room/formen.gd")

static var _cache := {}


## Ellipsoid mit Halbachsen r (Mitte im Ursprung). ao: unten etwas dunkler.
static func ei(r: Vector3, seg := 24, ao := 0.0) -> ArrayMesh:
	var key := "e%.4f,%.4f,%.4f|%d|%.2f" % [r.x, r.y, r.z, seg, ao]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ringe := maxi(6, seg / 2)
	for j in ringe:
		for i in seg:
			var quad := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			for t in [[0, 1, 2], [0, 2, 3]]:
				for k in t:
					var a := float(quad[k][0]) / seg * TAU
					var b := PI * 0.5 - float(quad[k][1]) / ringe * PI
					var e := Vector3(cos(b) * sin(a), sin(b), cos(b) * cos(a))
					var p := e * r
					var nrm := Vector3(e.x / r.x, e.y / r.y, e.z / r.z).normalized()
					var c := 1.0 - ao * (1.0 - smoothstep(-1.0, 0.2, e.y))
					st.set_color(Color(c, c, c))
					st.set_normal(nrm)
					st.set_uv(Vector2(float(quad[k][0]) / seg, float(quad[k][1]) / ringe))
					st.add_vertex(p)
	st.index()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## Glied: verjüngte Kapsel vom Gelenk (Ursprung, Radius r0) nach unten bis −laenge (Radius r1).
static func glied(r0: float, r1: float, laenge: float, seg := 18) -> ArrayMesh:
	var u := PackedVector2Array()
	for i in 5:
		var a := -PI * 0.5 + float(i) / 4.0 * PI * 0.5
		u.append(Vector2(r1 * cos(a), -laenge + r1 * sin(a)))
	for i in 5:
		var a := float(i) / 4.0 * PI * 0.5
		u.append(Vector2(r0 * cos(a), r0 * sin(a)))
	u[0].x = 0.0
	u[u.size() - 1].x = 0.0
	return F.dreh(u, seg)


## Mehrere Netze in einem: teile = [[Mesh, Transform3D], …]. schluessel für den Zwischenspeicher.
static func verbinden(schluessel: String, teile: Array) -> ArrayMesh:
	if schluessel != "" and _cache.has(schluessel):
		return _cache[schluessel]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in teile:
		st.append_from(t[0], 0, t[1])
	var mesh := st.commit()
	if schluessel != "":
		_cache[schluessel] = mesh
	return mesh


## Herz (für das Streicheln): zwei Kugeln und eine Spitze, flach gedrückt.
static func herz(g: float) -> ArrayMesh:
	var key := "herz%.3f" % g
	if _cache.has(key):
		return _cache[key]
	var k := ei(Vector3(g * 0.55, g * 0.55, g * 0.32), 16)
	var spitze := F.dreh(PackedVector2Array([Vector2(0, 0), Vector2(g * 0.62, g * 0.9), Vector2(0, g * 0.95)]), 16, [1])
	var mesh := verbinden("", [
		[k, Transform3D(Basis(), Vector3(-g * 0.42, g * 0.2, 0))],
		[k, Transform3D(Basis(), Vector3(g * 0.42, g * 0.2, 0))],
		[spitze, Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.52)), Vector3(0, -g * 0.85, 0))],
	])
	_cache[key] = mesh
	return mesh

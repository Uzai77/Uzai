extends RefCounted
## Eigene Formen für das Zimmer: Kisten mit Kanten wie am echten Möbel (kleine Fase von 1–3 mm als
## Standard, Rundung nur, wo etwas gepolstert oder gegossen ist), Drehkörper (Lampenschirm, Topf,
## Pokal, Schallplatte), Ringe und Blätter. Alles hier erzeugt, keine fremden Modelle. Jede Form
## bekommt Tangenten, damit Normalkarten der Materialien greifen.
##
## Im Kompatibilitäts-Renderer legt jede Form eine leichte Verdunklung nach unten in die
## Eckpunktfarbe (Kontaktschatten, als Ersatz für SSAO); in Forward+ übernehmen SSAO und SDFGI
## (ao_an = false, gesetzt von zimmer_welt.gd).
##
## Gleiche Formen werden nur einmal gebaut (Zwischenspeicher nach Maßen).
##
## Kiste, Drehkörper und Ring legen jede Ecke einmal an und verbinden sie über Nummern (_netz). Vorher
## entstand jedes Dreieck aus drei eigenen Ecken, die danach wieder zusammengesucht wurden – sechsmal so
## viele Aufrufe je Fläche; beim ersten Bau eines Zimmers lagen so rund 0,45 s in diesen drei Formen
## (gemessen, Standardzimmer). Die Netze sind dieselben (Ecke für Ecke verglichen).

static var _cache := {}
static var ao_an := true

## Je Fläche einer Kiste: Normale n, Achsen u und v mit u × v = −n (so zeigen alle Dreiecke nach außen).
const _KISTE_FLAECHEN := [
	[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
	[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
	[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
]


## Kiste: groesse in Metern (ganze Breite/Höhe/Tiefe), Mittelpunkt im Ursprung. rad: Kantenradius
## bzw. Fase; stufen 0: nach dem Radius (bis 4 mm eine gerade Fase, sonst drei Rundungsstufen).
## boden_ao: unten dunkler (steht auf etwas; nur Kompatibilität).
static func kiste(groesse: Vector3, rad := 0.0025, boden_ao := true, stufen := 0) -> ArrayMesh:
	if stufen <= 0:
		stufen = 1 if rad <= 0.004 else 3
	boden_ao = boden_ao and ao_an
	var key := "k%.3f,%.3f,%.3f|%.4f|%s|%d" % [groesse.x, groesse.y, groesse.z, rad, boden_ao, stufen]
	if _cache.has(key):
		return _cache[key]
	var h := groesse * 0.5
	var r := clampf(rad, 0.0005, minf(h.x, minf(h.y, h.z)) * 0.999)
	var inner := h - Vector3(r, r, r)
	# Unten etwas dunkler, als läge Licht nur gedämpft an (Kontaktschatten).
	var ao_bis := minf(0.16, h.y * 1.4)
	var orte := PackedVector3Array()
	var normalen := PackedVector3Array()
	var farben := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var index := PackedInt32Array()
	for fl: Array in _KISTE_FLAECHEN:
		var n: Vector3 = fl[0]
		var u: Vector3 = fl[1]
		var v: Vector3 = fl[2]
		var hu := absf(h.dot(u))
		var hv := absf(h.dot(v))
		var hn := absf(h.dot(n))
		var au := _stellen(hu, absf(inner.dot(u)), r, stufen)
		var av := _stellen(hv, absf(inner.dot(v)), r, stufen)
		var nu := au.size()
		var nv := av.size()
		var base := orte.size()
		for j in nv:
			for i in nu:
				var p: Vector3 = n * hn + u * au[i] + v * av[j]
				var c := p.clamp(-inner, inner)
				var d := p - c
				var nrm := d.normalized() if d.length() > 0.00001 else n
				var q := c + nrm * r
				var hell := lerpf(0.62, 1.0, smoothstep(0.0, ao_bis, q.y + h.y)) if boden_ao else 1.0
				orte.append(q)
				normalen.append(nrm)
				farben.append(Color(hell, hell, hell))
				uv.append(Vector2(au[i] + hu, hv - av[j]))
				uv2.append(Vector2((au[i] + hu) / (2.0 * hu), (hv - av[j]) / (2.0 * hv)))
		for j in nv - 1:
			for i in nu - 1:
				var a := base + j * nu + i
				index.append(a)
				index.append(a + 1)
				index.append(a + nu + 1)
				index.append(a)
				index.append(a + nu + 1)
				index.append(a + nu)
	var mesh := _netz(orte, normalen, farben, uv, uv2, index)
	_cache[key] = mesh
	return mesh


## Fertige Reihen (jede Ecke einmal, Dreiecke über Nummern) → Netz mit Tangenten (MikkTSpace wie bisher,
## damit die Normalkarten der Materialien gleich greifen). uv2 leer: ohne zweite UV.
static func _netz(orte: PackedVector3Array, normalen: PackedVector3Array, farben: PackedColorArray, uv: PackedVector2Array,
		uv2: PackedVector2Array, index: PackedInt32Array) -> ArrayMesh:
	var reihen: Array = []
	reihen.resize(Mesh.ARRAY_MAX)
	reihen[Mesh.ARRAY_VERTEX] = orte
	reihen[Mesh.ARRAY_NORMAL] = normalen
	reihen[Mesh.ARRAY_COLOR] = farben
	reihen[Mesh.ARRAY_TEX_UV] = uv
	if not uv2.is_empty():
		reihen[Mesh.ARRAY_TEX_UV2] = uv2
	reihen[Mesh.ARRAY_INDEX] = index
	var st := SurfaceTool.new()
	st.create_from_arrays(reihen)
	st.generate_tangents()
	return st.commit()


## Stellen entlang einer Achse: Rundung (nach tan verteilt, gleichmäßige Winkel), gerades Stück, Rundung.
static func _stellen(hu: float, iu: float, r: float, stufen: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var band: Array = []
	for k in range(stufen, 0, -1):
		band.append(iu + r * tan(float(k) / stufen * PI / 4.0))
	for b in band:
		out.append(-minf(b, hu))
	out.append(-iu)
	if iu > 0.0001:
		out.append(iu)
	band.reverse()
	for b in band:
		out.append(minf(b, hu))
	return out


## Drehkörper um die y-Achse aus einem Umriss [(radius, höhe), …] von unten nach oben.
## Normalen aus dem Umriss (weich); kanten: Indizes, an denen der Umriss einen Knick hat.
static func dreh(umriss: PackedVector2Array, segmente := 32, kanten: Array = [], ao := false) -> ArrayMesh:
	ao = ao and ao_an
	var key := "d%s|%d|%s|%s" % [str(umriss), segmente, str(kanten), ao]
	if _cache.has(key):
		return _cache[key]
	var n := umriss.size()
	var ymin := umriss[0].y
	for p in umriss:
		ymin = minf(ymin, p.y)
	# Länge entlang des Umrisses für v.
	var lang := PackedFloat32Array([0.0])
	for i in range(1, n):
		lang.append(lang[i - 1] + umriss[i].distance_to(umriss[i - 1]))
	var total := maxf(0.0001, lang[n - 1])
	var rmax := maxf(0.0001, _max_r(umriss))
	# Ringe: je Punkt des Umrisses einer; an einem Knick zwei (jede Seite mit ihrer eigenen Normalen).
	var ringe: Array = []                  # [Punkt im Umriss, Normale]
	var ring_vorn := PackedInt32Array()    # Ring des Punkts als Anfang seines Abschnitts
	var ring_hinten := PackedInt32Array()  # … und als Ende des Abschnitts davor
	for i in n:
		var nv := _umriss_normale(umriss, i, kanten, true)
		var nh := _umriss_normale(umriss, i, kanten, false)
		ring_vorn.append(ringe.size())
		if i < n - 1:
			ringe.append([i, nv])
		if i > 0 and (i == n - 1 or nh != nv):
			ring_hinten.append(ringe.size())
			ringe.append([i, nh])
		else:
			ring_hinten.append(ring_vorn[i])
	# Die Naht (Winkel 0 und TAU) liegt doppelt, damit die UV durchlaufen.
	var spalten := segmente + 1
	var winkel := PackedFloat64Array()
	var cs := PackedFloat64Array()
	var sn := PackedFloat64Array()
	for s in spalten:
		var ang := float(s) / segmente * TAU
		winkel.append(ang)
		cs.append(cos(ang))
		sn.append(sin(ang))
	var orte := PackedVector3Array()
	var normalen := PackedVector3Array()
	var farben := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	for e: Array in ringe:
		var pr: Vector2 = umriss[e[0]]
		var nr: Vector2 = e[1]
		var hell := lerpf(0.65, 1.0, smoothstep(ymin, ymin + 0.08, pr.y)) if ao else 1.0
		var farbe := Color(hell, hell, hell)
		var v := lang[e[0]] / total
		for s in spalten:
			orte.append(Vector3(pr.x * cs[s], pr.y, pr.x * sn[s]))
			normalen.append(Vector3(nr.x * cs[s], nr.y, nr.x * sn[s]).normalized())
			farben.append(farbe)
			uv.append(Vector2(winkel[s] / TAU, v))
			uv2.append(Vector2(0.5 + 0.5 * cs[s] * pr.x / rmax, 0.5 + 0.5 * sn[s] * pr.x / rmax))
	var index := PackedInt32Array()
	for i in n - 1:
		var a := ring_vorn[i] * spalten
		var b := ring_hinten[i + 1] * spalten
		var a_achse := umriss[i].x == 0.0
		var b_achse := umriss[i + 1].x == 0.0
		if a_achse or b_achse:
			# Deckel: Auf der Achse (Radius 0) fällt je Feld ein Dreieck zu einer Linie zusammen und bleibt weg. Die
			# übrigen hängen nur an der Spitze aneinander – jedes bekommt eigene Ecken, damit es (an einem harten
			# Rand) seine eigene Tangente behält wie bisher.
			if a_achse and b_achse:
				continue
			for s in segmente:
				for e: int in ([a + s, b + s + 1, b + s] if a_achse else [a + s, a + s + 1, b + s + 1]):
					index.append(orte.size())
					orte.append(orte[e])
					normalen.append(normalen[e])
					farben.append(farben[e])
					uv.append(uv[e])
					uv2.append(uv2[e])
			continue
		for s in segmente:
			index.append(a + s)
			index.append(b + s + 1)
			index.append(b + s)
			index.append(a + s)
			index.append(a + s + 1)
			index.append(b + s + 1)
	var mesh := _netz(orte, normalen, farben, uv, uv2, index)
	_cache[key] = mesh
	return mesh


static func _max_r(u: PackedVector2Array) -> float:
	var m := 0.0
	for p in u:
		m = maxf(m, p.x)
	return m


## Normale des Umrisses an Punkt i (nach außen). An Knicken je Seite die eigene Richtung.
static func _umriss_normale(u: PackedVector2Array, i: int, kanten: Array, nach_vorn: bool) -> Vector2:
	var n := u.size()
	var t := Vector2.ZERO
	if i in kanten:
		t = (u[i + 1] - u[i]) if nach_vorn and i + 1 < n else (u[i] - u[i - 1]) if i > 0 else (u[i + 1] - u[i])
	elif i == 0:
		t = u[1] - u[0]
	elif i == n - 1:
		t = u[n - 1] - u[n - 2]
	else:
		t = (u[i + 1] - u[i]).normalized() + (u[i] - u[i - 1]).normalized()
	t = t.normalized()
	# Umriss läuft von unten nach oben: außen ist rechts der Laufrichtung.
	return Vector2(t.y, -t.x)


## Zylinder mit gerundeten Kanten (Beine, Knöpfe, Dosen): Radius, Höhe, Kantenradius.
static func walze(radius: float, hoehe: float, kante := 0.002, segmente := 24, ao := false) -> ArrayMesh:
	var k := clampf(kante, 0.0005, minf(radius, hoehe * 0.5) * 0.99)
	var u := PackedVector2Array()
	u.append(Vector2(0.0, 0.0))
	for i in 5:
		var a := float(i) / 4.0 * PI * 0.5
		u.append(Vector2(radius - k + sin(a) * k, k - cos(a) * k))
	for i in 5:
		var a := float(i) / 4.0 * PI * 0.5
		u.append(Vector2(radius - k + cos(a) * k, hoehe - k + sin(a) * k))
	u.append(Vector2(0.0, hoehe))
	return dreh(u, segmente, [0, u.size() - 1], ao)


## Ring (Torus) mit großem Radius R und Dicke r, in der xy-Ebene; bogen < TAU für Henkel.
static func ring(R: float, r: float, bogen := TAU, seg := 28, rseg := 10) -> ArrayMesh:
	var key := "r%.4f,%.4f,%.3f,%d,%d" % [R, r, bogen, seg, rseg]
	if _cache.has(key):
		return _cache[key]
	var orte := PackedVector3Array()
	var normalen := PackedVector3Array()
	var farben := PackedColorArray()
	var uv := PackedVector2Array()
	var reihe := rseg + 1
	for i in seg + 1:
		var a := float(i) / seg * bogen
		var mitte := Vector3(cos(a) * R, sin(a) * R, 0.0)
		for j in reihe:
			var b := float(j) / rseg * TAU
			var nrm := Vector3(cos(a) * cos(b), sin(a) * cos(b), sin(b))
			orte.append(mitte + nrm * r)
			normalen.append(nrm)
			farben.append(Color.WHITE)
			uv.append(Vector2(float(i) / seg, float(j) / rseg))
	var index := PackedInt32Array()
	for i in seg:
		for j in rseg:
			var e := i * reihe + j
			index.append(e)
			index.append(e + reihe + 1)
			index.append(e + reihe)
			index.append(e)
			index.append(e + 1)
			index.append(e + reihe + 1)
	var mesh := _netz(orte, normalen, farben, uv, PackedVector2Array(), index)
	_cache[key] = mesh
	return mesh


## Blatt: gewölbte Fläche entlang der Mittelrippe (Länge l, Breite b), zur Spitze hin hängend.
## form 0: breites Herzblatt (Monstera, die Lappen greifen etwas hinter den Stiel), 1: schmal
## (Olive). Die Eckpunktfarbe macht die Rippe heller und die Ränder dunkler.
## Beidseitig sichtbar über das Material (cull_disabled).
static func blatt(l: float, b: float, biegung := 0.25, form := 0) -> ArrayMesh:
	var key := "b%.3f,%.3f,%.3f,%d" % [l, b, biegung, form]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nl := 14
	var nb := 5
	var pts: Array = []
	var cols: Array = []
	for i in nl + 1:
		var t := float(i) / nl
		var breite := b * 0.5 * pow(sin(PI * t), 0.55) if form == 0 else b * 0.5 * (1.0 - pow(absf(t * 2.0 - 1.0), 2.2))
		var y := sin(t * PI * 0.5) * biegung * l * 0.6 - t * t * biegung * l * 0.5
		var z := (t - (0.14 if form == 0 else 0.0)) * l
		var row: Array = []
		var crow: Array = []
		for j in nb * 2 + 1:
			var s := float(j - nb) / nb
			var wolb := -absf(s) * breite * 0.28 + s * s * breite * 0.1
			row.append(Vector3(s * breite, y + wolb, z))
			var c := lerpf(0.78, 1.1, pow(1.0 - absf(s), 3.0)) * lerpf(0.82, 1.0, t)
			crow.append(Color(c, c, c))
		pts.append(row)
		cols.append(crow)
	for i in nl:
		for j in nb * 2:
			var q := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			for t in [[0, 1, 2], [0, 2, 3]]:
				for k in t:
					var p: Vector3 = pts[q[k][0]][q[k][1]]
					st.set_color(cols[q[k][0]][q[k][1]])
					st.set_uv(Vector2(p.x / b + 0.5, p.z / l))
					st.add_vertex(p)
	st.generate_normals()
	st.generate_tangents()
	st.index()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## Stoffbahn mit Falten (Vorhang): Breite, Höhe, Faltenzahl, Tiefe der Falten.
static func vorhang(breite: float, hoehe: float, falten := 7, tiefe := 0.05) -> ArrayMesh:
	var key := "v%.3f,%.3f,%d,%.3f" % [breite, hoehe, falten, tiefe]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := falten * 8
	var ny := 6
	for i in nx:
		for j in ny:
			var quad := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			for t in [[0, 1, 2], [0, 2, 3]]:
				for k in t:
					var u := float(quad[k][0]) / nx
					var v := float(quad[k][1]) / ny
					var ph := u * falten * TAU
					# Unten etwas weiter geschwungen als oben (der Stoff fällt).
					var amp := tiefe * (0.7 + 0.3 * (1.0 - v))
					var z := sin(ph) * amp
					var dz := cos(ph) * amp * falten * TAU / breite
					var nrm := Vector3(-dz, 0.0, 1.0).normalized()
					var c := lerpf(0.72, 1.0, 0.5 + 0.5 * sin(ph))
					st.set_color(Color(c, c, c))
					st.set_normal(nrm)
					st.set_uv(Vector2(u * breite, v * hoehe))
					st.add_vertex(Vector3((u - 0.5) * breite, (1.0 - v) * hoehe, z))
	st.generate_tangents()
	st.index()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## Schlauch: ein Querschnitt (Ellipse mit den Halbachsen breite × dicke) entlang eines Pfads gezogen –
## gebogenes Holz (Beine, Haken), Riemen und Stoff, der fällt (Mantel, Ärmel, Schal, Mütze).
## pfad: Stützpunkte, weich verbunden (Catmull-Rom, je Abschnitt `fein` Schritte); breite und dicke je
## Stützpunkt. quer: Richtung der Breite – ein Wert (am Anfang, danach ohne Verdrehen mitgeführt) oder
## einer je Stützpunkt (ein Schal dreht sich über die Schulter). Winkel 0 liegt auf quer, PI/2 auf
## Tangente × quer. falten (Anzahl, Tiefe am Anfang, Tiefe am Ende; Meter): weiche Längsfalten, ab 12
## regelmäßig wie Rippen (Strick); um den Winkel `glatt` (Knopfleiste, < 0: nirgends) bleibt der Stoff
## ruhig. Die Normalen kommen aus der fertigen Fläche (die Falten fangen das Licht), die Täler werden
## über die Eckpunktfarbe dunkler. enden (Anfang, Ende): Helligkeit der Deckel – 1 zu wie ein Stück
## Holz, dunkler eingezogen wie eine Öffnung (Ärmel, Saum), < 0 offen (steckt in etwas). UV in Metern.
static func schlauch(pfad: PackedVector3Array, breite: PackedFloat32Array, dicke: PackedFloat32Array, quer: PackedVector3Array,
		seg := 16, fein := 4, falten := Vector3.ZERO, glatt := -1.0, enden := Vector2.ONE) -> ArrayMesh:
	var key := "s%s|%s|%s|%s|%d|%d|%s|%.3f|%s" % [pfad, breite, dicke, quer, seg, fein, falten, glatt, enden]
	if _cache.has(key):
		return _cache[key]
	var n := pfad.size()
	var je_punkt := quer.size() == n
	var pts := PackedVector3Array()
	var bs := PackedFloat32Array()
	var ds := PackedFloat32Array()
	var qs := PackedVector3Array()
	for i in n - 1:
		var vor := maxi(i - 1, 0)
		var nach := mini(i + 2, n - 1)
		for k in fein + (1 if i == n - 2 else 0):
			var t := float(k) / fein
			pts.append(pfad[i].cubic_interpolate(pfad[i + 1], pfad[vor], pfad[nach], t))
			bs.append(maxf(0.0005, cubic_interpolate(breite[i], breite[i + 1], breite[vor], breite[nach], t)))
			ds.append(maxf(0.0005, cubic_interpolate(dicke[i], dicke[i + 1], dicke[vor], dicke[nach], t)))
			if je_punkt:
				qs.append(quer[i].lerp(quer[i + 1], t))
	var m := pts.size()
	# Rahmen je Ring: Tangente, Breite (quer, senkrecht zur Tangente), Dicke.
	var ts := PackedVector3Array()
	var ws := PackedVector3Array()
	var ns := PackedVector3Array()
	var w := quer[0]
	for i in m:
		var t := (pts[mini(i + 1, m - 1)] - pts[maxi(i - 1, 0)]).normalized()
		if je_punkt:
			w = qs[i]
		w -= t * w.dot(t)
		if w.length_squared() < 1e-8:
			w = t.cross(Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT)
		w = w.normalized()
		ts.append(t)
		ws.append(w)
		ns.append(t.cross(w))
	# Ringe mit Falten; die Naht (Winkel 0 und TAU) liegt doppelt, damit die UV durchlaufen.
	var lage: Array[PackedVector3Array] = []
	var tal: Array[PackedFloat32Array] = []
	for i in m:
		var s := float(i) / maxf(1.0, m - 1)
		var tiefe := lerpf(falten.y, falten.z, s)
		var ring := PackedVector3Array()
		var tr := PackedFloat32Array()
		for j in seg + 1:
			var a := float(j % seg) / seg * TAU
			var f := 0.0
			if tiefe > 0.0:
				if falten.x >= 12.0:
					f = sin(falten.x * a)
				else:
					f = 0.62 * sin(falten.x * a + s * 1.9) + 0.38 * sin((falten.x + 3.0) * a + 1.7 - s * 1.2)
				if glatt >= 0.0:
					f *= 1.0 - exp(-pow(angle_difference(a, glatt) / 0.5, 2.0))
			var ne := (ws[i] * (cos(a) / bs[i]) + ns[i] * (sin(a) / ds[i])).normalized()
			ring.append(pts[i] + ws[i] * (bs[i] * cos(a)) + ns[i] * (ds[i] * sin(a)) + ne * (f * tiefe))
			tr.append(f * clampf(tiefe / 0.008, 0.0, 1.0))
		lage.append(ring)
		tal.append(tr)
	var laenge := PackedFloat32Array([0.0])
	for i in range(1, m):
		laenge.append(laenge[i - 1] + pts[i].distance_to(pts[i - 1]))
	var nrm: Array[PackedVector3Array] = []
	for i in m:
		var row := PackedVector3Array()
		for j in seg + 1:
			var jj := j % seg
			var dj := lage[i][(jj + 1) % seg] - lage[i][(jj + seg - 1) % seg]
			var di := lage[mini(i + 1, m - 1)][j] - lage[maxi(i - 1, 0)][j]
			var nn := di.cross(dj).normalized()
			if nn.dot(lage[i][j] - pts[i]) < 0.0:
				nn = -nn
			row.append(nn)
		nrm.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in m - 1:
		var u0 := _umfang(bs[i], ds[i]) / seg
		var u1 := _umfang(bs[i + 1], ds[i + 1]) / seg
		for j in seg:
			var q := [[i, j, u0], [i, j + 1, u0], [i + 1, j, u1], [i + 1, j + 1, u1]]
			# Godot zeichnet Dreiecke, deren Ecken von vorn im Uhrzeigersinn liegen.
			var vorn: Vector3 = nrm[i][j] + nrm[i + 1][j + 1]
			var dreh_um := (lage[i + 1][j] - lage[i][j]).cross(lage[i][j + 1] - lage[i][j]).dot(vorn) > 0.0
			for k in ([0, 1, 2, 1, 3, 2] if dreh_um else [0, 2, 1, 1, 2, 3]):
				var e: Array = q[k]
				var c := 1.0 - 0.3 * maxf(0.0, -tal[e[0]][e[1]])
				st.set_color(Color(c, c, c))
				st.set_normal(nrm[e[0]][e[1]])
				st.set_uv(Vector2(float(e[1]) * float(e[2]), laenge[e[0]]))
				st.add_vertex(lage[e[0]][e[1]])
	for e in 2:
		var hell := enden.x if e == 0 else enden.y
		if hell < 0.0:
			continue
		var i := 0 if e == 0 else m - 1
		var aus := -ts[i] if e == 0 else ts[i]
		var mitte := pts[i] - aus * (minf(bs[i], ds[i]) * 0.6 if hell < 0.95 else 0.0)
		for j in seg:
			var p1 := lage[i][j]
			var p2 := lage[i][j + 1]
			if (p1 - mitte).cross(p2 - mitte).dot(aus) > 0.0:
				p1 = lage[i][j + 1]
				p2 = lage[i][j]
			var tri: Array[Vector3] = [mitte, p1, p2]
			for k in 3:
				var p := tri[k]
				var c := hell * (0.75 if k == 0 and hell < 0.95 else 1.0)
				st.set_color(Color(c, c, c))
				st.set_normal(aus)
				st.set_uv(Vector2((p - pts[i]).dot(ws[i]), (p - pts[i]).dot(ns[i])))
				st.add_vertex(p)
	st.generate_tangents()
	st.index()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


## Umfang einer Ellipse mit den Halbachsen a und b (Ramanujan).
static func _umfang(a: float, b: float) -> float:
	return PI * (3.0 * (a + b) - sqrt((3.0 * a + b) * (a + 3.0 * b)))


## Ebene Fläche (Rechteck) in der xy-Ebene, Vorderseite +z.
static func flaeche(breite: float, hoehe: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(breite, hoehe)
	return q


## Platte mit eigenem Umriss (Seitenwand eines Automaten, ein Fell auf dem Boden): der Umriss
## [(z, y), …] (Meter, beliebig herum) wird dicke breit entlang x gezogen, die Kanten mit einer Fase.
## Die beiden Seiten tragen UV über den ganzen Umriss (0 … 1, für ein Motiv), die Kanten UV in Metern.
static func profil(umriss: PackedVector2Array, dicke: float, fase := 0.003) -> ArrayMesh:
	var key := "p%s|%.4f|%.4f" % [str(umriss), dicke, fase]
	if _cache.has(key):
		return _cache[key]
	var u := umriss.duplicate()
	if Geometry2D.is_polygon_clockwise(u):
		u.reverse()
	var n := u.size()
	# Eckpunkt-Normalen des Umrisses (nach außen) für die Fase.
	var aussen := PackedVector2Array()
	for i in n:
		var a := u[(i - 1 + n) % n]
		var b := u[i]
		var c := u[(i + 1) % n]
		var n1 := Vector2(b.y - a.y, a.x - b.x).normalized()
		var n2 := Vector2(c.y - b.y, b.x - c.x).normalized()
		aussen.append((n1 + n2).normalized())
	var f := minf(fase, dicke * 0.45)
	var innen := PackedVector2Array()
	for i in n:
		innen.append(u[i] - aussen[i] * f)
	var lo := u[0]
	var hi := u[0]
	for p in u:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var groesse := (hi - lo).max(Vector2(0.0001, 0.0001))
	var h := dicke * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	var tris := Geometry2D.triangulate_polygon(innen)
	for seite: float in [-1.0, 1.0]:
		var nrm := Vector3(seite, 0, 0)
		for k in range(0, tris.size(), 3):
			# Gegen den Uhrzeigersinn im Umriss (z, y): von +x gesehen vorn (Godot: im Uhrzeigersinn vorn).
			var ccw := (innen[tris[k + 1]] - innen[tris[k]]).cross(innen[tris[k + 2]] - innen[tris[k]]) > 0.0
			var reihe := [tris[k], tris[k + 1], tris[k + 2]] if (seite > 0.0) == ccw else [tris[k], tris[k + 2], tris[k + 1]]
			for idx: int in reihe:
				var p := innen[idx]
				st.set_normal(nrm)
				st.set_uv(Vector2((p.x - lo.x) / groesse.x if seite > 0.0 else 1.0 - (p.x - lo.x) / groesse.x, 1.0 - (p.y - lo.y) / groesse.y))
				st.set_uv2(Vector2((p.x - lo.x) / groesse.x, 1.0 - (p.y - lo.y) / groesse.y))
				st.add_vertex(Vector3(seite * h, p.y, p.x))
	# Kante: Fase vorn, gerades Stück, Fase hinten – je Abschnitt ein Streifen.
	var ringe := [[innen, -h, -1.0], [u, -h + f, 0.0], [u, h - f, 0.0], [innen, h, 1.0]]
	var lang := 0.0
	for i in n:
		var j := (i + 1) % n
		var l := u[i].distance_to(u[j])
		for r in 3:
			var ra: Array = ringe[r]
			var rb: Array = ringe[r + 1]
			var pa: PackedVector2Array = ra[0]
			var pb: PackedVector2Array = rb[0]
			var q := [[pa[i], float(ra[1]), float(ra[2]), aussen[i], lang], [pa[j], float(ra[1]), float(ra[2]), aussen[j], lang + l],
				[pb[j], float(rb[1]), float(rb[2]), aussen[j], lang + l], [pb[i], float(rb[1]), float(rb[2]), aussen[i], lang]]
			for t in [[0, 1, 2], [0, 2, 3]]:
				for k: int in t:
					var e: Array = q[k]
					var p2: Vector2 = e[0]
					var o: Vector2 = e[3]
					st.set_normal(Vector3(float(e[2]) * 0.7, o.y, o.x).normalized())
					st.set_uv(Vector2(float(e[4]), float(e[1]) + h))
					st.set_uv2(Vector2(0.0, 0.0))
					st.add_vertex(Vector3(float(e[1]), p2.y, p2.x))
		lang += l
	st.generate_tangents()
	st.index()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh

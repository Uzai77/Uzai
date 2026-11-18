extends "res://tests/probe_uebergaenge.gd"
## Probe „Cursor und Halten“ (docs/PLAN_GEFUEHL.md, Paket B): Bildfolgen des Cursors in Guide,
## Einstellungen, Seitenleiste und Regal, Halten einer Richtung und Anstoßen am Rand. Läuft mit
## --fixed-fps 60: jedes Bild ist genau 1/60 s Spielzeit, egal wie lange das Speichern dauert.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 --fixed-fps 60 \
##       -- --demo --no-boot --uzai-script=res://tests/probe_cursor.gd --uzai-out=<ordner>
##
## Je Übergang: <out>/<name>/messung.csv (je Bild Helligkeit, Änderung zum Vorbild,
## dazu der Stand des alten und des neuen Cursors), kurve.png, ausgewählte Bilder. Dazu
## <out>/abnahme.txt: je Zeile „ok“ oder „FEHLT“ mit Grund.
##
## Gemessen wird auf 480 × 270. Bewegt ist ein Bild ab 3 % der größten Änderung, still darunter ein
## Fünftel davon.
## Abnahme (Abschnitt 2.3): Antwort im ersten Bild (neuer Cursor ≥ 70 %, alter ≤ 30 %), Helligkeit
## nie unter min(vorher, nachher) − 8, letzter bewegter Schritt ≤ 40 % des größten, kein Stillstand
## zwischen bewegten Bildern, letzte Bewegung ≤ 300 ms. Halten: Regal-Tempo schwankt < 1,4 : 1,
## Rand stößt einmal an.

const W_S := 480
const H_S := 270
const W_T := 96
const H_T := 54
const BEWEGT := 0.03
const GRENZE_MS := 300

var _sum: Array = []
var _abnahme: Array = []
var _vorher: Control = null


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	_bilder = Config.path("probe_bilder")
	DirAccess.make_dir_recursive_absolute(_bilder)
	await _saeen()
	# Die laufende Musik der Vorführung steht still: ihr Pegel und Fortschritt bewegten sonst das
	# Messfeld um den Cursor.
	if not Music.now.is_empty():
		Music.now["playing"] = false
		Music.updated.emit()
	main.goto("games")
	await wait(2.0)
	await _waehle("g:", 1)
	await wait(0.6)

	# 1. Guide: eine Zeile runter, dann mehrmals (über Abschnittslinien).
	main.toggle_guide()
	await wait(1.2)
	await _aufnahme("c01_guide_runter", func() -> void: _dir("down"), 24, [0, 1, 2, 3, 4, 6, 8, 12, 18, 24], true)
	await wait(0.6)
	await _ueber_linie("c02_guide_abschnitt")
	await wait(0.6)
	Nav._fire("guide")
	await wait(1.2)

	# 2. Regal: ein Cover nach rechts, dann rechts halten (Tempo), dann am Anfang links anstoßen.
	await _waehle("g:", 0)
	await wait(0.8)
	await _aufnahme("c03_cover_rechts", func() -> void: _dir("right"), 30, [0, 1, 2, 3, 4, 6, 9, 12, 18, 30], true)
	await wait(0.8)
	await _waehle("g:", 0)
	await wait(0.8)
	await _regal_halten("c04_regal_halten", 110)
	await wait(1.5)

	# 3. Seitenleiste (Y) und darin runter.
	await _waehle("g:", 1)
	await wait(0.6)
	Nav._fire("y")
	await wait(1.0)
	await _aufnahme("c05_leiste_runter", func() -> void: _dir("down"), 24, [0, 1, 2, 3, 4, 6, 8, 12, 18, 24], true)
	await wait(0.6)
	Nav._fire("b")
	await wait(1.0)

	# 4. Einstellungen: in den Inhalt, eine Zeile runter, halten, oben am Rand halten.
	main.goto("settings")
	await wait(2.0)
	Nav._fire("right")
	await wait(1.0)
	await _aufnahme("c06_einst_runter", func() -> void: _dir("down"), 24, [0, 1, 2, 3, 4, 6, 8, 12, 18, 24], true)
	await wait(0.8)
	await _halten("c07_einst_halten", "down", 72)
	await wait(0.8)
	await _halten("c08_einst_rand", "up", 150, true)
	await wait(0.8)

	# 5. Dasselbe mit „Animationen reduzieren“.
	Config.set_value("theme.reduce_motion", true)
	await wait(0.3)
	await _aufnahme("c09_einst_runter_ruhig", func() -> void: _dir("down"), 24, [0, 1, 2, 3, 4, 6, 8, 12, 18, 24], true)
	Config.set_value("theme.reduce_motion", false)
	await wait(0.8)

	var f := FileAccess.open(out.path_join("zusammenfassung.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_sum) + "\n")
	f.close()
	var fa := FileAccess.open(out.path_join("abnahme.txt"), FileAccess.WRITE)
	fa.store_string("\n".join(_abnahme) + "\n")
	fa.close()
	print("\n".join(_sum))
	print("\n".join(_abnahme))


func _dir(d: String) -> void:
	_vorher = Nav.focused()
	Nav._fire(d)


## So weit runter, bis zwischen alter und neuer Zeile eine Abschnittslinie liegt (größerer Abstand).
func _ueber_linie(name: String) -> void:
	for i in 12:
		var a := Nav.focused()
		if a == null:
			return
		var next := _naechste_unten(a)
		if next and next.get_global_rect().position.y - a.get_global_rect().end.y > 12.0 and _stand(a) >= 0.0 and _stand(next) >= 0.0:
			await _aufnahme(name, func() -> void: _dir("down"), 24, [0, 1, 2, 3, 4, 6, 8, 12, 18, 24], true)
			return
		Nav._fire("down")
		await wait(0.5)
	_sum.append(name + ": keine Abschnittslinie gefunden")


func _naechste_unten(a: Control) -> Control:
	var best: Control = null
	var ar := a.get_global_rect()
	for c in Nav.focusables(Nav.scope_root()):
		var r := c.get_global_rect()
		if c == a or r.position.y < ar.end.y - 4.0:
			continue
		if best == null or r.position.y < best.get_global_rect().position.y:
			best = c
	return best


## Stand eines Cursors (0…1): eigene Variable der Zeile oder Meta uz_f; Cover: _focus_t.
static func _stand(c: Variant) -> float:
	if not (c is Control) or not is_instance_valid(c):
		return -1.0
	for k in ["_f", "_focus_t"]:
		var v: Variant = (c as Control).get(k)
		if v is float:
			return float(v)
	return float((c as Control).get_meta("uz_f", -1.0))


# --- Aufnahme -------------------------------------------------------------------------------------

func _aufnahme(name: String, los: Callable, n: int, pick: Array, cursor := false) -> void:
	var dir := out.path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	var gross: Array = []
	var klein: Array = []
	var notiz: Array = []
	await RenderingServer.frame_post_draw
	_merke(gross, klein)
	notiz.append("")
	los.call()
	var neu := Nav.focused()
	var alt := _vorher
	var erst := Vector2(-1, -1)
	var gl0 := false
	# Gemessen wird beim Cursor nur um alte und neue Zeile (sonst zählt jede Uhr und jedes Licht mit).
	var feld := Rect2()
	if cursor and alt and neu and not name.contains("cover"):
		feld = alt.get_global_rect().merge(neu.get_global_rect()).grow(48.0)
	var daten: Array = []
	for i in n:
		await RenderingServer.frame_post_draw
		_merke(gross, klein)
		var s := Vector2(_stand(alt), _stand(neu))
		if i == 0:
			erst = s
			gl0 = _gleitet(neu)
		daten.append(_daten(alt, neu))
		notiz.append("alt=%.2f neu=%.2f rahmen=%s" % [s.x, s.y, str(daten.back())])
	var r := _auswerten(name, dir, klein, gross, pick, notiz, feld, cursor)
	if cursor:
		r.append_array(_bewegung(name, daten))
		# Gleitet der Rahmen, zeichnet ihn die neue Zeile voll (ihr eigener Stand zählt dann nicht).
		var gl := gl0
		var ok1 := gl or (erst.y >= 0.69 and (erst.x < 0.0 or erst.x <= 0.31))
		_abnahme.append("%s %s: erstes Bild alt %.2f, neu %.2f%s" % ["ok   " if ok1 else "FEHLT", name, erst.x, erst.y, " (Rahmen gleitet)" if gl else ""])
	_abnahme.append_array(r)


## Was sich am Cursor bewegt, je Bild: Lage und Größe des gezeichneten Rahmens in ganzen Pixeln
## (gleitender Rahmen, sonst die neue Auswahl samt Wachsen; im Regal dazu die Lage der Reihe) und
## der Stand von altem und neuem Cursor.
func _daten(alt: Control, neu: Control) -> Array:
	var r := Rect2()
	if _gleitet(neu):
		var L: Variant = load("res://src/ui/components/liste.gd")
		r = (L as Object).call("gleiter_lage")
	elif is_instance_valid(neu):
		# Der Rahmen, den die Zeile selbst zeichnet (Liste.cursor merkt ihn in uz_zr), sonst die Fläche.
		var eigen: Rect2 = neu.get_meta("uz_zr", Rect2(Vector2.ZERO, neu.size))
		r = neu.get_global_transform() * eigen
	var reihe := _regal_von(neu)
	var off := roundf(float(reihe.get("_off"))) if reihe else 0.0
	return [roundf(r.position.x), roundf(r.position.y), roundf(r.size.x), roundf(r.size.y), off,
			snappedf(_stand(alt), 0.01), snappedf(_stand(neu), 0.01)]


## Abnahme aus den Daten (die Bildänderung sagt bei einem 2 px schmalen Rahmen wenig über das Tempo):
## letzte Bewegung ≤ 300 ms, letzter Schritt ≤ 40 % des größten (in Pixeln), kein Stillstand.
func _bewegung(name: String, daten: Array) -> Array:
	var px: Array = [0.0]
	var irgend: Array = [true]
	for i in range(1, daten.size()):
		var a: Array = daten[i - 1]
		var b: Array = daten[i]
		# daten[0] ist das erste Bild nach dem Druck; die Indizes zählen ab dort (+1 Bild).
		var d := 0.0
		for k in 5:
			d += absf(float(b[k]) - float(a[k]))
		px.append(d)
		irgend.append(d > 0.0 or absf(float(b[5]) - float(a[5])) > 0.004 or absf(float(b[6]) - float(a[6])) > 0.004)
	var erst := irgend.find(true)
	var letzt := irgend.rfind(true)
	var groesst := 0.0
	var letzt_px := -1
	for i in px.size():
		groesst = maxf(groesst, float(px[i]))
		if float(px[i]) > 0.0:
			letzt_px = i
	var gruende: Array = []
	if (letzt + 1) * 1000.0 / 60.0 > GRENZE_MS:
		gruende.append("letzte Bewegung bei %d ms" % roundi((letzt + 1) * 1000.0 / 60.0))
	if letzt_px > 0 and float(px[letzt_px]) > 0.4 * groesst:
		gruende.append("letzter Schritt %d px von größtem %d px" % [roundi(float(px[letzt_px])), roundi(groesst)])
	if erst > 0:
		for i in range(erst, letzt):
			if not irgend[i]:
				gruende.append("Stillstand bei %d ms" % roundi((i + 1) * 1000.0 / 60.0))
				break
	var was := "Rahmen: größter Schritt %d px, letzter %d px, letzte Bewegung %d ms" % [roundi(groesst), roundi(float(px[letzt_px])) if letzt_px > 0 else 0, roundi((maxi(letzt, 0) + 1) * 1000.0 / 60.0)]
	_sum.append(name + ": " + was)
	return ["%s %s: %s%s" % ["ok   " if gruende.is_empty() else "FEHLT", name, was, (" – " + ", ".join(gruende)) if not gruende.is_empty() else ""]]


func _gleitet(c: Control) -> bool:
	var L: Variant = load("res://src/ui/components/liste.gd")
	return L != null and (L as Script).has_method("gleitet_zu") and (L as Object).call("gleitet_zu") == c


## Halten einer Richtung (echte Eingabe): Fokuswechsel je Bild; am Rand zählt die Probe die Anstöße.
func _halten(name: String, d: String, n: int, rand := false) -> void:
	var dir := out.path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	var gross: Array = []
	var klein: Array = []
	var notiz: Array = []
	var down := InputEventAction.new()
	down.action = "uz_" + d
	down.pressed = true
	await RenderingServer.frame_post_draw
	_merke(gross, klein)
	notiz.append("")
	Input.parse_input_event(down)
	var wechsel: Array = []
	var prev: Control = Nav.focused()
	var stoesse := 0
	var letzter := 0
	for i in n:
		await RenderingServer.frame_post_draw
		_merke(gross, klein)
		var f := Nav.focused()
		if f != prev:
			wechsel.append(roundi((i + 1) * 1000.0 / 60.0))
			prev = f
		# Anstoß: jeder Anstoß legt an der Zeile (oder ihrer Reihe) eine neue Bewegung „uz_bump“ an.
		var tw: Variant = null
		for nd in [f, f.get_parent() if f else null]:
			if nd is Control and (nd as Control).has_meta("uz_bump"):
				tw = (nd as Control).get_meta("uz_bump")
		var tid := (tw as Object).get_instance_id() if tw is Object else 0
		if tid != 0 and tid != letzter:
			stoesse += 1
		letzter = tid
		notiz.append("fokus=%s stoesse=%d" % [str(f.get_meta("uz_key", f.name)) if f else "-", stoesse])
	var up := InputEventAction.new()
	up.action = "uz_" + d
	up.pressed = false
	Input.parse_input_event(up)
	var gaps: Array = []
	for i in range(1, wechsel.size()):
		gaps.append(int(wechsel[i]) - int(wechsel[i - 1]))
	_auswerten(name, dir, klein, gross, [0, 6, 12, 24, 36, 48, 60, n], notiz)
	var line := "%s: %d Schritte, Abstände %s, Anstöße %d" % [name, wechsel.size(), str(gaps), stoesse]
	_sum.append(line)
	if rand:
		_abnahme.append("%s %s: Rand stößt %d-mal an (gehalten %d ms)" % ["ok   " if stoesse == 1 else "FEHLT", name, stoesse, roundi(n * 1000.0 / 60.0)])


## Regal halten: Lage der Reihe je Bild, daraus das Tempo; Schwankung im gleichmäßigen Teil.
func _regal_halten(name: String, n: int) -> void:
	var dir := out.path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	var shelf: Control = _regal_von(Nav.focused())
	if shelf == null:
		_sum.append(name + ": kein Regal")
		return
	var gross: Array = []
	var klein: Array = []
	var notiz: Array = []
	var down := InputEventAction.new()
	down.action = "uz_right"
	down.pressed = true
	await RenderingServer.frame_post_draw
	_merke(gross, klein)
	notiz.append("")
	Input.parse_input_event(down)
	var offs: Array = []
	var wechsel: Array = [0]
	var prev := Nav.focused()
	for i in n:
		await RenderingServer.frame_post_draw
		_merke(gross, klein)
		if Nav.focused() != prev:
			prev = Nav.focused()
			wechsel.append(i)
		var sh := _regal_von(Nav.focused())
		if sh:
			shelf = sh
		var o := float(shelf.get("_off")) if is_instance_valid(shelf) else 0.0
		offs.append(o)
		notiz.append("off=%.1f" % o)
	var up := InputEventAction.new()
	up.action = "uz_right"
	up.pressed = false
	Input.parse_input_event(up)
	_auswerten(name, dir, klein, gross, [0, 12, 24, 30, 36, 42, 48, 60, 72, n], notiz)
	# Gleichmäßiger Teil: zwischen dem 6. und 10. Schritt (Takt 120 ms; davor 162 ms, danach 96 ms –
	# das Beschleunigen selbst zählt nicht als Schwanken).
	var v: Array = []
	var von: int = int(wechsel[6]) + 1 if wechsel.size() > 10 else 44
	var bis: int = int(wechsel[10]) + 1 if wechsel.size() > 10 else offs.size()
	for i in range(maxi(von, 1), mini(bis, offs.size())):
		var dv := float(offs[i]) - float(offs[i - 1])
		if dv <= 0.05:
			break
		v.append(dv)
	var lo := INF
	var hi := 0.0
	for x in v:
		lo = minf(lo, float(x))
		hi = maxf(hi, float(x))
	var ratio := hi / maxf(lo, 0.001) if not v.is_empty() else INF
	var line := "%s: Schritte bei Bild %s; Tempo zwischen Schritt 6 und 10: %.1f … %.1f px/Bild über %d Bilder, Verhältnis %.2f : 1" % [name, str(wechsel), lo, hi, v.size(), ratio]
	_sum.append(line)
	_abnahme.append("%s %s: Tempo schwankt %.2f : 1 (Ziel < 1,4)" % ["ok   " if ratio < 1.4 and v.size() >= 8 else "FEHLT", name, ratio])


func _regal_von(c: Control) -> Control:
	var n: Node = c
	while n:
		if n is Control and "_off" in n and n.has_method("items"):
			return n as Control
		n = n.get_parent()
	return null


func _auswerten(name: String, dir: String, klein: Array, gross: Array, pick: Array, notiz: Array, feld := Rect2(), nur_hell := false) -> Array:
	var csv := ["bild;ms;hell;diff;notiz"]
	var prev := PackedByteArray()
	var diffs: Array = []
	var hells: Array = []
	# Messfeld in den Bildern (480 × 270): ganzer Schirm oder das Feld um den Cursor.
	var k_s := float(W_S) / get_viewport().get_visible_rect().size.x
	var fr := Rect2i(0, 0, W_S, H_S)
	if feld.size != Vector2.ZERO:
		fr = Rect2i(Rect2(feld.position * k_s, feld.size * k_s)).intersection(Rect2i(0, 0, W_S, H_S))
	for i in gross.size():
		var d: PackedByteArray = (gross[i] as Image).get_data()
		var sum := 0.0
		var dsum := 0.0
		var px := 0
		for yy in range(fr.position.y, fr.end.y):
			for xx in range(fr.position.x, fr.end.x):
				var j := (yy * W_S + xx) * 3
				var y := 0.2126 * d[j] + 0.7152 * d[j + 1] + 0.0722 * d[j + 2]
				sum += y
				px += 1
				if prev.size() == d.size():
					dsum += absf(y - (0.2126 * prev[j] + 0.7152 * prev[j + 1] + 0.0722 * prev[j + 2]))
		px = maxi(px, 1)
		hells.append(sum / px)
		diffs.append(dsum / px if prev.size() == d.size() else 0.0)
		csv.append("%d;%d;%.2f;%.3f;%s" % [i, roundi(i * 1000.0 / 60.0), sum / px, float(diffs[i]), notiz[i]])
		prev = d
	var cf := FileAccess.open(dir.path_join("messung.csv"), FileAccess.WRITE)
	cf.store_string("\n".join(csv) + "\n")
	cf.close()
	var k := 0
	for p in pick:
		var i := clampi(int(p), 0, gross.size() - 1)
		(gross[i] as Image).save_png(dir.path_join("f%02d_%04dms.png" % [k, roundi(i * 1000.0 / 60.0)]))
		k += 1
	var chart := Image.create(1920, 120, false, Image.FORMAT_RGB8)
	chart.fill(Color(0.06, 0.06, 0.07))
	var dmax := 0.5
	for v in diffs:
		dmax = maxf(dmax, float(v))
	var bw := maxi(2, int(1920.0 / maxf(1.0, float(diffs.size()))))
	for i in diffs.size():
		var h := int(100.0 * float(diffs[i]) / dmax)
		chart.fill_rect(Rect2i(i * bw + 1, 110 - h, bw - 2, h), Color(0.92, 0.92, 0.94))
		var hy := 110 - int(100.0 * float(hells[i]) / 255.0)
		chart.fill_rect(Rect2i(i * bw, clampi(hy - 1, 0, 118), bw, 3), Color(0.55, 0.75, 0.95))
	for p in pick:
		var i2 := clampi(int(p), 0, diffs.size() - 1)
		chart.fill_rect(Rect2i(i2 * bw, 112, bw, 6), Color(0.95, 0.6, 0.45))
	chart.save_png(dir.path_join("kurve.png"))
	# Abnahme
	var lo := minf(float(hells[0]), float(hells[hells.size() - 1]))
	var hmin := INF
	for h in hells:
		hmin = minf(hmin, float(h))
	var groesst := 0.0
	for i in range(1, diffs.size()):
		groesst = maxf(groesst, float(diffs[i]))
	# Bewegt: mindestens 3 % des größten Schritts (und nicht nur Rauschen).
	var bewegt := maxf(BEWEGT, groesst * 0.03)
	var still := bewegt * 0.2
	var letzt := -1
	for i in range(1, diffs.size()):
		if float(diffs[i]) >= bewegt:
			letzt = i
	var stillstand := false
	var erst := -1
	for i in range(1, diffs.size()):
		if float(diffs[i]) >= bewegt:
			erst = i
			break
	if erst > 0:
		for i in range(erst, letzt):
			if float(diffs[i]) < still:
				stillstand = true
	var letzt_ms := roundi(letzt * 1000.0 / 60.0) if letzt > 0 else 0
	var schritt := float(diffs[letzt]) / maxf(groesst, 0.001) if letzt > 0 else 0.0
	var gruende: Array = []
	if hmin < lo - 8.0:
		gruende.append("Helligkeit %.1f unter %.1f" % [hmin, lo - 8.0])
	if schritt > 0.4:
		gruende.append("letzter Schritt %.0f %% des größten" % (schritt * 100.0))
	if stillstand:
		gruende.append("Stillstand zwischen Bewegungen")
	var halten := name.contains("halten") or name.contains("rand")
	if nur_hell:
		# Cursor: Tempo und Ende kommen aus den Daten (_bewegung), hier zählt nur die Helligkeit.
		gruende = gruende.filter(func(g: String) -> bool: return g.begins_with("Helligkeit"))
	elif letzt_ms > GRENZE_MS and not halten:
		gruende.append("letzte Bewegung bei %d ms" % letzt_ms)
	var line := "%s: %d Bilder, Helligkeit %.1f → %.1f (min %.1f), größte Änderung %.2f, letzte Bewegung %d ms (%.0f %% des größten)" % [
		name, klein.size(), float(hells[0]), float(hells[hells.size() - 1]), hmin, groesst, letzt_ms, schritt * 100.0]
	_sum.append(line)
	print(line)
	if halten:
		return []
	var grund := (": " + ", ".join(gruende)) if not gruende.is_empty() else ""
	return ["%s %s%s%s" % ["ok   " if gruende.is_empty() else "FEHLT", name, " (Helligkeit)" if nur_hell else "", grund]]


func _merke(gross: Array, klein: Array) -> void:
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var s := img.duplicate() as Image
	s.resize(W_S, H_S, Image.INTERPOLATE_BILINEAR)
	gross.append(s)
	var t := img.duplicate() as Image
	t.resize(W_T, H_T, Image.INTERPOLATE_BILINEAR)
	klein.append(t)

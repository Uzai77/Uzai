extends "res://tests/probe_uebergaenge.gd"
## Probe „Takt“ (docs/PLAN_GEFUEHL.md, Paket A): Bildfolgen der Übergänge von Bereichen,
## Unterbereichen, Apps, Seitenleisten, Dialogen, Einstellungen und Bibliothek, mit der Abnahme
## aus Abschnitt 2.3. Läuft mit --fixed-fps 60: jedes Bild ist genau 1/60 s Spielzeit, egal wie
## lange das Speichern dauert.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 --fixed-fps 60 \
##       -- --demo --no-boot --uzai-script=res://tests/probe_takt.gd --uzai-out=<ordner>
##
## Je Übergang: <out>/<name>/messung.csv (je Bild mittlere Helligkeit und Änderung zum Vorbild,
## 0–255, auf 96 × 54 verkleinert), kurve.png, ausgewählte Bilder f*_NNNNms.png. Dazu
## <out>/abnahme.txt mit je einer Zeile „ok“ oder „FEHLT“ und dem Grund.
##
## Abnahme je Übergang:
##   - Helligkeit nie unter dem Minimum von vorher und nachher minus 8 (kein Loch, kein Blitz),
##   - der letzte bewegte Schritt höchstens 40 % des größten (kein Ruck am Ende); ebenso bricht
##     keine Bewegung nach einem großen Schritt (ab der Hälfte des größten) schlagartig ab,
##   - kein Stillstand zwischen bewegten Bildern,
##   - letzte Bewegung spätestens nach GRENZE_MS (Bereich 450 ms),
##   - kein Nachrucken: nach dem größten Schritt kein einzelnes spätes Bild mit Änderung über
##     NACH_RUCK, das mindestens 2,5-mal so groß ist wie das Bild davor, das fast stand (unter
##     NACH_STAND) – ein Pixel, das allein fällt, wenn sonst alles steht (PLAN_GEFUEHL2 R4).
## Bewegt ist ein Bild, dessen Änderung zum Vorbild mindestens BEWEGT beträgt; still eines unter STILL.
## Ein stilles Bild zählt als Stillstand, wenn danach noch drei Bilder in Folge deutlich (DEUTLICH)
## bewegt sind.

const W_S := 480
const H_S := 270
const W_T := 96
const H_T := 54
const BEWEGT := 0.1
const STILL := 0.02
const DEUTLICH := 0.5
const GRENZE_MS := 450
const NACH_RUCK := 1.0
const NACH_STAND := 0.6

var _sum: Array = []
var _abnahme: Array = []
var _fehlt := 0


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	_bilder = Config.path("probe_bilder")
	DirAccess.make_dir_recursive_absolute(_bilder)
	await _saeen()
	main.goto("games")
	await wait(2.0)
	await _waehle("g:", 1)
	await wait(0.6)

	# Bereich wechseln (RT: Spiele → Shop) und zurück (LT).
	await _aufnahme("04_bereich_rt", func() -> void: Nav._fire("rt"), 40, [0, 1, 2, 3, 4, 6, 8, 12, 18, 24, 30, 40])
	await wait(3.0)
	# Unterbereich (RB im Shop), einmal auch mit „Animationen reduzieren“. Vorher einmal hin und
	# zurück: Gemessen wird die Bewegung, nicht das erste Laden der Bilder (das blendet der Shop
	# selbst ein, sobald ein Bild da ist).
	Nav._fire("rb")
	await wait(2.0)
	Nav._fire("lb")
	await wait(2.0)
	await _aufnahme("05_unterbereich_rb", func() -> void: Nav._fire("rb"), 30, [0, 1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 30])
	await wait(1.5)
	Config.set_value("theme.reduce_motion", true)
	await _aufnahme("05r_unterbereich_lb_ruhig", func() -> void: Nav._fire("lb"), 30, [0, 1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 30])
	Config.set_value("theme.reduce_motion", false)
	await wait(1.5)
	await _aufnahme("04b_bereich_lt", func() -> void: Nav._fire("lt"), 40, [0, 1, 2, 3, 4, 6, 8, 12, 18, 24, 30, 40])
	await wait(2.0)
	await _waehle("g:", 1)
	await wait(0.8)

	# Seitenleiste (Y: Optionen) auf und zu.
	await _aufnahme("07_leiste_auf", func() -> void: Nav._fire("y"), 30, [0, 1, 2, 3, 4, 6, 9, 12, 18, 30])
	await wait(1.0)
	await _aufnahme("08_leiste_zu", func() -> void: Nav._fire("b"), 20, [0, 1, 2, 3, 4, 6, 8, 10, 14, 20])
	await wait(1.0)

	# Dialog auf und zu.
	await _aufnahme("09_dialog_auf", func() -> void:
		main.open_dialog("Spiel ausblenden?", "Es bleibt installiert und kommt über die Bibliothek zurück.",
				[["Ausblenden", func() -> void: pass], ["Abbrechen", func() -> void: pass]], "warning")
	, 30, [0, 1, 2, 3, 4, 6, 9, 12, 18, 30])
	await wait(1.0)
	await _aufnahme("10_dialog_zu", func() -> void: Nav._fire("b"), 20, [0, 1, 2, 3, 4, 6, 8, 10, 14, 20])
	await wait(1.0)

	# Einstellungen: Kategorie wechseln und eine Unterseite („…“) auf und zu.
	main.goto("settings")
	await wait(2.0)
	await _aufnahme("12_einst_kategorie", func() -> void: Nav._fire("down"), 30, [0, 1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 30])
	await wait(1.5)
	var more := _erstes("more:", main.sections.settings)
	if more:
		Nav.focus(more, true)
		await wait(1.0)
		await _aufnahme("13_einst_unterseite_auf", func() -> void: Nav._fire("a"), 30, [0, 1, 2, 3, 4, 6, 9, 12, 18, 30])
		await wait(1.0)
		await _aufnahme("14_einst_unterseite_zu", func() -> void: Nav._fire("b"), 20, [0, 1, 2, 3, 4, 6, 8, 10, 14, 20])
		await wait(1.0)
	else:
		_sum.append("keine Unterseite gefunden")

	# Apps: App wechseln (RB).
	main.goto("apps")
	await wait(2.5)
	await _aufnahme("15_apps_rb", func() -> void: Nav._fire("rb"), 40, [0, 1, 2, 3, 4, 6, 8, 12, 18, 24, 30, 40])
	await wait(1.5)

	# Bibliothek auf und zu.
	main.goto("games")
	await wait(1.5)
	await _aufnahme("16_bibliothek_auf", func() -> void: main.open_library("alle", "Alle Spiele"), 40, [0, 1, 2, 3, 4, 6, 9, 12, 18, 24, 30, 40])
	await wait(1.5)
	await _aufnahme("16b_bibliothek_zu", func() -> void: Nav._fire("b"), 24, [0, 1, 2, 3, 4, 6, 8, 10, 14, 24])
	await wait(1.0)

	_abnahme.append("Ergebnis: %s" % ("alles ok" if _fehlt == 0 else "%d Übergänge verfehlen die Abnahme" % _fehlt))
	var f := FileAccess.open(out.path_join("zusammenfassung.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_sum) + "\n")
	f.close()
	var a := FileAccess.open(out.path_join("abnahme.txt"), FileAccess.WRITE)
	a.store_string("\n".join(_abnahme) + "\n")
	a.close()
	print("\n".join(_sum))
	print("\n".join(_abnahme))


func _erstes(prefix: String, root: Node) -> Control:
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE and str(c.get_meta("uz_key", "")).begins_with(prefix):
			return c
	return null


# --- Aufnahme -------------------------------------------------------------------------------------

## n Bilder nach dem Auslösen (Bild 0 kurz davor); pick: welche Bilder einzeln gespeichert werden.
func _aufnahme(name: String, los: Callable, n: int, pick: Array) -> void:
	var dir := out.path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	var gross: Array = []
	var klein: Array = []
	await RenderingServer.frame_post_draw
	_merke(gross, klein)
	los.call()
	for i in n:
		await RenderingServer.frame_post_draw
		_merke(gross, klein)
	var csv := ["bild;ms;hell;diff"]
	var prev := PackedByteArray()
	var diffs: Array = []
	var hells: Array = []
	for i in klein.size():
		var d: PackedByteArray = (klein[i] as Image).get_data()
		var sum := 0.0
		var dsum := 0.0
		for j in range(0, d.size(), 3):
			var y := 0.2126 * d[j] + 0.7152 * d[j + 1] + 0.0722 * d[j + 2]
			sum += y
			if prev.size() == d.size():
				dsum += absf(y - (0.2126 * prev[j] + 0.7152 * prev[j + 1] + 0.0722 * prev[j + 2]))
		var px := d.size() / 3
		hells.append(sum / px)
		diffs.append(dsum / px if prev.size() == d.size() else 0.0)
		csv.append("%d;%d;%.2f;%.3f" % [i, roundi(i * 1000.0 / 60.0), float(hells[i]), float(diffs[i])])
		prev = d
	var cf := FileAccess.open(dir.path_join("messung.csv"), FileAccess.WRITE)
	cf.store_string("\n".join(csv) + "\n")
	cf.close()
	var k := 0
	for p in pick:
		var i := clampi(int(p), 0, gross.size() - 1)
		(gross[i] as Image).save_png(dir.path_join("f%02d_%04dms.png" % [k, roundi(i * 1000.0 / 60.0)]))
		k += 1
	_kurve(dir, diffs, hells, pick)
	var urteil := abnahme(diffs, hells, GRENZE_MS)
	if not urteil.ok:
		_fehlt += 1
	_abnahme.append("%s: %s – %s" % [name, "ok" if urteil.ok else "FEHLT", urteil.text])
	var line := "%s: %d Bilder, Helligkeit %.1f → %.1f (min %.1f), größte Änderung %.2f bei Bild %d" % [
		name, klein.size(), float(hells[0]), float(hells.back()), _min(hells), _max(diffs), diffs.find(_max(diffs))]
	_sum.append(line)
	print(line, "\n  ", _abnahme.back())


## Die Abnahme aus docs/PLAN_GEFUEHL.md 2.3 über eine Messreihe (Bild 0 = vorher).
static func abnahme(diffs: Array, hells: Array, grenze_ms: int) -> Dictionary:
	var gruende: Array = []
	var boden := minf(float(hells[0]), float(hells.back())) - 8.0
	var tief := _min(hells)
	if tief < boden:
		gruende.append("Loch: Helligkeit %.1f unter %.1f" % [tief, boden])
	var first := -1
	var last := -1
	var top := 0.0
	for i in range(1, diffs.size()):
		var v := float(diffs[i])
		top = maxf(top, v)
		if v >= BEWEGT:
			if first < 0:
				first = i
			last = i
	if last < 0:
		return { "ok": gruende.is_empty(), "text": "keine Bewegung" + ("; " + "; ".join(gruende) if not gruende.is_empty() else "") }
	if float(diffs[last]) > 0.4 * top:
		gruende.append("Ruck am Ende: letzter Schritt %.2f, größter %.2f" % [float(diffs[last]), top])
	# Ruck mittendrin: ein großer Schritt nach dem ersten bewegten Bild, nach dem die Bewegung
	# schlagartig abbricht (Ausblenden mit ease-in endet so) – zählt wie ein Ruck am Ende.
	for i in range(first + 1, last):
		var v := float(diffs[i])
		if v >= 0.5 * top and v > float(diffs[i - 1]) and float(diffs[i + 1]) < 0.4 * v:
			gruende.append("Ruck bei %d ms: Schritt %.2f, danach %.2f" % [roundi(i * 1000.0 / 60.0), v, float(diffs[i + 1])])
			break
	# Stillstand: ein Bild ohne Änderung, nach dem die Bewegung noch einmal anhaltend weitergeht
	# (drei Bilder in Folge deutlich bewegt) – eine Pause mitten im Übergang. Im Auslauf unter einem
	# Pixel je Bild treppt die Bewegung (Pixelraster: einzelne 1-px-Schritte mit stillen Bildern
	# dazwischen), das ist kein Stillstand.
	for i in range(first + 1, last):
		if float(diffs[i]) < STILL and _weiter_bewegt(diffs, i + 1, last):
			gruende.append("Stillstand bei %d ms" % roundi(i * 1000.0 / 60.0))
			break
	# Nachrucken: ein später Einzelschritt, nachdem es fast stand.
	var gross := diffs.find(_max(diffs.slice(1))) if diffs.size() > 1 else 0
	for i in range(gross + 2, diffs.size()):
		var v := float(diffs[i])
		var vor := float(diffs[i - 1])
		if v > NACH_RUCK and vor < NACH_STAND and v > 2.5 * vor:
			gruende.append("Nachrucken bei %d ms: Schritt %.2f nach %.2f" % [roundi(i * 1000.0 / 60.0), v, vor])
			break
	var ende_ms := roundi(last * 1000.0 / 60.0)
	if ende_ms > grenze_ms:
		gruende.append("letzte Bewegung erst bei %d ms" % ende_ms)
	var info := "größter Schritt %.2f, letzter %.2f, Ende %d ms, Helligkeit min %.1f (Boden %.1f)" % [top, float(diffs[last]), ende_ms, tief, boden]
	return { "ok": gruende.is_empty(), "text": info + ("; " + "; ".join(gruende) if not gruende.is_empty() else "") }


static func _weiter_bewegt(diffs: Array, von: int, bis: int) -> bool:
	for j in range(von, bis - 1):
		if float(diffs[j]) >= DEUTLICH and float(diffs[j + 1]) >= DEUTLICH and float(diffs[j + 2]) >= DEUTLICH:
			return true
	return false


func _kurve(dir: String, diffs: Array, hells: Array, pick: Array) -> void:
	var chart := Image.create(1920, 120, false, Image.FORMAT_RGB8)
	chart.fill(Color(0.06, 0.06, 0.07))
	var dmax_all := 0.5
	for v in diffs:
		dmax_all = maxf(dmax_all, float(v))
	var bw := maxi(2, int(1920.0 / maxf(1.0, float(diffs.size()))))
	for i in diffs.size():
		var h := int(100.0 * float(diffs[i]) / dmax_all)
		chart.fill_rect(Rect2i(i * bw + 1, 110 - h, bw - 2, h), Color(0.92, 0.92, 0.94))
		var hy := 110 - int(100.0 * float(hells[i]) / 255.0)
		chart.fill_rect(Rect2i(i * bw, clampi(hy - 1, 0, 118), bw, 3), Color(0.55, 0.75, 0.95))
	for p in pick:
		var i2 := clampi(int(p), 0, diffs.size() - 1)
		chart.fill_rect(Rect2i(i2 * bw, 112, bw, 6), Color(0.95, 0.6, 0.45))
	chart.save_png(dir.path_join("kurve.png"))


func _merke(gross: Array, klein: Array) -> void:
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var s := img.duplicate() as Image
	s.resize(W_S, H_S, Image.INTERPOLATE_BILINEAR)
	gross.append(s)
	var t := img.duplicate() as Image
	t.resize(W_T, H_T, Image.INTERPOLATE_BILINEAR)
	klein.append(t)


static func _min(a: Array) -> float:
	var m := INF
	for v in a:
		m = minf(m, float(v))
	return m


static func _max(a: Array) -> float:
	var m := -INF
	for v in a:
		m = maxf(m, float(v))
	return m

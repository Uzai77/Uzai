extends "res://tests/probe_takt.gd"
## Probe „Bereiche“ (Plan „Gefühl 2“, Paket E2 „Ränder“): Shop, Freunde, Profil, Apps, Filme,
## Videos, Musik, Tastatur, Mitteilungen, „Neu“, Ausschalten, Ruhe, Einrichtung und das Halten in
## Reihen – je Übergang eine Bildfolge mit der Abnahme aus PLAN_GEFUEHL 2.3 (probe_takt.gd), dazu
## je Bild das Klangprotokoll (Sfx._recent: welcher Klang, ob ein späterer ihn ersetzt hat), der
## Zustand (Ebenen, Auswahl) und eine Suche nach Sprüngen nach der Hauptbewegung. Obendrauf die
## Abnahme von E2 (Zeilen „E2 …“): kein harter Schnitt im Shop, B aus dem Genre auf die
## Herkunftskachel, kein Neuaufbau von selbst, das Rampenlicht steht, solange es gewählt ist, das
## Licht der Freunde fällt nie ab, das Profil springt nicht, Medien-Kacheln im einen Cursor-Takt
## ohne Lichtstreif in Graphit, Einrichtung ohne Skalieren, Aufwachen ohne Guide-Klang und Toast,
## „launch“ nirgends außer beim Spielstart.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 --fixed-fps 60 \
##       -- --demo --no-boot --uzai-script=res://tests/probe_bereiche.gd --uzai-out=<ordner> [--uzai-teil=shop]
##
## Teile (--uzai-teil=…, ohne: alle): shop, bereiche, system, halten. Je Teil <out>/<teil>_abnahme.txt
## und <teil>_zusammenfassung.txt.

const AE := preload("res://src/core/apps_extern.gd")
const WhatsNewL := preload("res://src/ui/layers/whats_new.gd")
const Wizard := preload("res://src/ui/layers/setup_wizard.gd")

## Abnahme E2: so groß darf die Änderung in einem Bild höchstens sein (kein harter Schnitt).
const SCHNITT := 15.0

var _notizen: Array = []


func _aufn(name: String, los: Callable, n: int, pick: Array = [], feld := Rect2(), grenze := GRENZE_MS, watch := Callable()) -> Dictionary:
	var dir := out.path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	var gross: Array = []
	var klein: Array = []
	var zeilen: Array = []
	var gesehen := {}
	var klang: Array = []      # [bild, name, ersetzt_bei]
	await RenderingServer.frame_post_draw
	_merke(gross, klein)
	_klang(gesehen, klang, -1)
	zeilen.append(_zustand() + (" " + str(watch.call()) if watch.is_valid() else ""))
	los.call()
	for i in n:
		await RenderingServer.frame_post_draw
		_merke(gross, klein)
		_klang(gesehen, klang, i + 1)
		zeilen.append(_zustand() + (" " + str(watch.call()) if watch.is_valid() else ""))
	# Messreihe (ganzer Schirm und Feld).
	var csv := ["bild;ms;hell;diff;feld_hell;feld_diff;zustand"]
	var prev := PackedByteArray()
	var diffs: Array = []
	var hells: Array = []
	var fh: Array = []
	var fd: Array = []
	var k_s := float(W_S) / get_viewport().get_visible_rect().size.x
	var fr := Rect2i(0, 0, W_S, H_S)
	if feld.size != Vector2.ZERO:
		fr = Rect2i(Rect2(feld.position * k_s, feld.size * k_s)).intersection(Rect2i(0, 0, W_S, H_S))
	var prev_g := PackedByteArray()
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
		prev = d
		# Feld auf 480 × 270
		var g: PackedByteArray = (gross[i] as Image).get_data()
		var s2 := 0.0
		var d2 := 0.0
		var p2 := 0
		for yy in range(fr.position.y, fr.end.y):
			for xx in range(fr.position.x, fr.end.x):
				var jj := (yy * W_S + xx) * 3
				var y2 := 0.2126 * g[jj] + 0.7152 * g[jj + 1] + 0.0722 * g[jj + 2]
				s2 += y2
				p2 += 1
				if prev_g.size() == g.size():
					d2 += absf(y2 - (0.2126 * prev_g[jj] + 0.7152 * prev_g[jj + 1] + 0.0722 * prev_g[jj + 2]))
		p2 = maxi(p2, 1)
		fh.append(s2 / p2)
		fd.append(d2 / p2 if prev_g.size() == g.size() else 0.0)
		prev_g = g
		csv.append("%d;%d;%.2f;%.3f;%.2f;%.3f;%s" % [i, roundi(i * 1000.0 / 60.0), float(hells[i]), float(diffs[i]), float(fh[i]), float(fd[i]), str(zeilen[i])])
	var cf := FileAccess.open(dir.path_join("messung.csv"), FileAccess.WRITE)
	cf.store_string("\n".join(csv) + "\n")
	cf.close()
	if pick.is_empty():
		pick = [0, 1, 2, 3, 4, 6, 9, 12, 18, 24, mini(36, n), n]
	var k := 0
	for p in pick:
		var i := clampi(int(p), 0, gross.size() - 1)
		(gross[i] as Image).save_png(dir.path_join("f%02d_%04dms.png" % [k, roundi(i * 1000.0 / 60.0)]))
		k += 1
	_kurve(dir, diffs, hells, pick)
	# Sprünge nach der Hauptbewegung: ein einzelnes Bild mit deutlicher Änderung zwischen ruhigen.
	var spruenge: Array = []
	for i in range(4, diffs.size()):
		var v := float(diffs[i])
		var vor := float(diffs[i - 1])
		var nach := float(diffs[i + 1]) if i + 1 < diffs.size() else 0.0
		if v >= 0.8 and v > 3.0 * maxf(vor, 0.15) and v > 3.0 * maxf(nach, 0.15):
			var r := _wo(klein[i - 1], klein[i])
			spruenge.append("Bild %d (%d ms): Änderung %.2f in %s" % [i, roundi(i * 1000.0 / 60.0), v, str(r)])
			(gross[i - 1] as Image).save_png(dir.path_join("sprung_%02d_a.png" % i))
			(gross[i] as Image).save_png(dir.path_join("sprung_%02d_b.png" % i))
	# Klangprotokoll
	var kl: Array = []
	for e in klang:
		kl.append("%s @%d ms%s" % [str(e[1]), roundi(float(e[0]) * 1000.0 / 60.0), (" (ersetzt bei %d ms)" % roundi(float(e[2]) * 1000.0 / 60.0)) if int(e[2]) >= 0 else ""])
	var urteil := abnahme(diffs, hells, grenze)
	var feld_txt := ""
	if feld.size != Vector2.ZERO:
		feld_txt = " | Feld: Helligkeit %.1f → %.1f (min %.1f)" % [float(fh[0]), float(fh.back()), _min(fh)]
	if not urteil.ok:
		_fehlt += 1
	_abnahme.append("%s: %s – %s%s | Klang: %s%s" % [name, "ok" if urteil.ok else "FEHLT", urteil.text, feld_txt,
			", ".join(kl) if not kl.is_empty() else "keiner", (" | Sprünge: " + "; ".join(spruenge)) if not spruenge.is_empty() else ""])
	var line := "%s: %d Bilder, Helligkeit %.1f → %.1f (min %.1f), größte Änderung %.2f bei Bild %d" % [
		name, klein.size(), float(hells[0]), float(hells.back()), _min(hells), _max(diffs), diffs.find(_max(diffs))]
	_sum.append(line)
	print(line, "\n  ", _abnahme.back())
	return { "diffs": diffs, "hells": hells, "klang": kl, "spruenge": spruenge }


## Neue Klänge seit dem letzten Bild (Sfx._recent), dazu: wurde ein gemerkter Klang verstummt?
func _klang(gesehen: Dictionary, klang: Array, bild: int) -> void:
	var rec: Variant = Sfx.get("_recent")
	if rec is Array:
		for e in rec:
			var key := "%s|%s|%s" % [str(e[0]), str(e[2]), str(e[4])]
			if gesehen.has(key):
				continue
			gesehen[key] = true
			if bild >= 0:
				klang.append([bild, str(e[2]), -1, e[3]])
	for e in klang:
		if int(e[2]) >= 0:
			continue
		var p: Variant = e[3]
		if p is AudioStreamPlayer and is_instance_valid(p) and (p as AudioStreamPlayer).volume_db <= -79.0:
			e[2] = bild


## Ebenen, Auswahl, Mitteilungen je Bild (für die Messreihe).
func _zustand() -> String:
	var f := Nav.focused()
	var key := str(f.get_meta("uz_key", f.name)) if f else "-"
	var top := Nav.top_layer()
	return "ebenen=%d top=%s fokus=%s" % [Nav.layers.size(), (top.get_script().resource_path.get_file() if top and top.get_script() else "-"), key]


## Wo sich zwei kleine Bilder (96 × 54) unterscheiden: Rechteck in Schirm-Pixeln.
func _wo(a: Image, b: Image) -> Rect2i:
	var da := a.get_data()
	var db := b.get_data()
	var x0 := W_T
	var y0 := H_T
	var x1 := -1
	var y1 := -1
	for y in H_T:
		for x in W_T:
			var j := (y * W_T + x) * 3
			var d := absi(int(da[j]) - int(db[j])) + absi(int(da[j + 1]) - int(db[j + 1])) + absi(int(da[j + 2]) - int(db[j + 2]))
			if d > 30:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0 * 20, y0 * 20, (x1 - x0 + 1) * 20, (y1 - y0 + 1) * 20)


func _schreiben(datei: String) -> void:
	_abnahme.append("Ergebnis: %s" % ("alles ok" if _fehlt == 0 else "%d Übergänge verfehlen die Abnahme" % _fehlt))
	var f := FileAccess.open(out.path_join(datei + "_zusammenfassung.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_sum) + "\n\n" + "\n".join(_notizen) + "\n")
	f.close()
	var a := FileAccess.open(out.path_join(datei + "_abnahme.txt"), FileAccess.WRITE)
	a.store_string("\n".join(_abnahme) + "\n")
	a.close()
	print("\n".join(_abnahme))
	print("\n".join(_notizen))


func _notiz(t: String) -> void:
	_notizen.append(t)
	print("NOTIZ ", t)


func _schliessen() -> void:
	while Nav.top_layer():
		Nav.top_layer().close()
		await wait(0.35)


## Erstes sichtbares, wählbares Element mit diesem uz_key-Anfang irgendwo unter root.
func _such(prefix: String, root: Node = null) -> Control:
	return _erstes(prefix, root if root else main)


func _vorbereiten() -> void:
	Config.set_value("controller.glyphs", "xbox")
	_bilder = Config.path("probe_bilder")
	DirAccess.make_dir_recursive_absolute(_bilder)
	await _saeen()
	if not Music.now.is_empty():
		Music.now["playing"] = false
		Music.updated.emit()


func run() -> void:
	var teil := ""
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--uzai-teil="):
			teil = str(a).substr(12)
	await _vorbereiten()
	for t in ["shop", "bereiche", "system", "halten"]:
		if teil == "" or teil == t:
			_sum.clear()
			_abnahme.clear()
			_notizen.clear()
			_fehlt = 0
			await call("_teil_" + t)
			_schreiben(t)


## Zeile der E2-Abnahme (zählt wie ein verfehlter Übergang).
func _e2(name: String, ok: bool, text: String) -> void:
	if not ok:
		_fehlt += 1
	_abnahme.append("E2 %s: %s – %s" % [name, "ok" if ok else "FEHLT", text])
	print(_abnahme.back())


## Letzte bewegte Stelle (ms) und größte Änderung einer Messreihe.
static func _ende_ms(diffs: Array) -> int:
	var last := 0
	for i in range(1, diffs.size()):
		if float(diffs[i]) >= BEWEGT:
			last = i
	return roundi(last * 1000.0 / 60.0)


static func _groesste(diffs: Array, ab := 1) -> float:
	var m := 0.0
	for i in range(ab, diffs.size()):
		m = maxf(m, float(diffs[i]))
	return m


## Mitteilungen, die gerade auf dem Schirm stehen.
func _toast_n() -> int:
	var b: Variant = Toasts.get("_box")
	return (b as Node).get_child_count() if b is Node and is_instance_valid(b) else 0


func _alle_klaenge(r: Dictionary) -> String:
	return ", ".join(r.get("klang", []))


var _launch := []


func _merke_launch(name: String, r: Dictionary) -> void:
	for k in r.get("klang", []):
		if str(k).begins_with("launch"):
			_launch.append(name)


# --- Shop -----------------------------------------------------------------------------------------

func _teil_shop() -> void:
	var upd := [0]
	Store.updated.connect(func() -> void: upd[0] += 1)
	main.goto("games")
	await wait(2.0)
	await _waehle("g:", 1)
	await wait(0.8)
	var shop: Control = main.sections.shop
	var w_shop := func() -> String:
		var kid := shop.get_child(0) if shop.get_child_count() > 0 else null
		return "seite=%d upd=%d" % [kid.get_instance_id() % 100000 if kid else 0, upd[0]]
	var r := await _aufn("s01_shop_betreten", func() -> void: Nav._fire("rt"), 180,
			[0, 1, 2, 3, 4, 6, 9, 12, 18, 24, 30, 45, 60, 90, 120, 180], Rect2(), 450, w_shop)
	_merke_launch("s01", r)
	# 10 s ohne Eingabe: baut sich der Shop von selbst neu auf?
	var seite_alt := shop.get_child(0).get_instance_id() if shop.get_child_count() > 0 else 0
	var neu := 0
	for i in 600:
		await get_tree().process_frame
		var sid := shop.get_child(0).get_instance_id() if shop.get_child_count() > 0 else 0
		if sid != seite_alt:
			neu += 1
			seite_alt = sid
	_e2("shop_ruhe", neu == 0, "Neuaufbauten in den 10 s nach dem Betreten ohne Eingabe: %d (Store meldete %d-mal)" % [neu, upd[0]])
	# Rampenlicht: rechts blättern, dann gewählt 15 s stehen lassen.
	var hero := _such("shop:hero", shop)
	if hero:
		Nav.focus(hero, true)
		await wait(0.6)
		r = await _aufn("s02_rampenlicht_rechts", func() -> void: Nav._fire("right"), 48,
				[0, 1, 2, 3, 4, 6, 9, 12, 18, 24, 36, 48], hero.get_global_rect(), 700)
		var idx0 := int(hero.get("idx"))
		await wait(15.0)
		_e2("rampenlicht_gewaehlt", is_instance_valid(hero) and int(hero.get("idx")) == idx0 and Nav.focused() == hero,
				"gewählt 15 s: Platz %d → %d" % [idx0, int(hero.get("idx")) if is_instance_valid(hero) else -1])
	else:
		_notiz("kein Rampenlicht")
	# Kategorie (Pille) → Genre, B zurück auf die Pille.
	var cat := _such("cat:", shop)
	if cat:
		var ck := str(cat.get_meta("uz_key", ""))
		Nav.focus(cat, true)
		await wait(1.0)
		r = await _aufn("s03_kategorie_a", func() -> void: Nav._fire("a"), 45, [], Rect2(), 450, w_shop)
		_e2("kategorie_schnitt", _groesste(r.diffs) <= SCHNITT, "größte Änderung in einem Bild %.1f (≤ %.0f)" % [_groesste(r.diffs), SCHNITT])
		await wait(2.0)
		r = await _aufn("s04_genre_b_zurueck", func() -> void: Nav._fire("b"), 40, [], Rect2(), 450, w_shop)
		await wait(0.3)
		var fk := str(Nav.focused().get_meta("uz_key", "")) if Nav.focused() else "-"
		_e2("genre_zurueck", _groesste(r.diffs) <= SCHNITT and _ende_ms(r.diffs) <= 450 and fk == ck,
				"größte Änderung %.1f, Ende %d ms, Auswahl %s (Herkunft %s)" % [_groesste(r.diffs), _ende_ms(r.diffs), fk, ck])
		await wait(1.0)
	else:
		_notiz("keine Kategorie")
	# Genre-Kachel im Raster der Genres → Genre-Seite → B auf die Kachel.
	main.goto("shop", "genres")
	await wait(2.0)
	var gt := _such("genre:", shop)
	if gt:
		var gk := ""
		for c in Nav.focusables(shop):
			if str(c.get_meta("uz_key", "")).begins_with("genre:"):
				gt = c
		gk = str(gt.get_meta("uz_key", ""))
		Nav.focus(gt, true)
		await wait(1.0)
		r = await _aufn("s05_genre_kachel_a", func() -> void: Nav._fire("a"), 45, [], Rect2(), 450, w_shop)
		_e2("genre_auf_schnitt", _groesste(r.diffs) <= SCHNITT, "größte Änderung %.1f" % _groesste(r.diffs))
		await wait(1.5)
		r = await _aufn("s05b_genre_kachel_b", func() -> void: Nav._fire("b"), 40, [], Rect2(), 450, w_shop)
		await wait(0.3)
		var fk2 := str(Nav.focused().get_meta("uz_key", "")) if Nav.focused() else "-"
		_e2("genre_kachel_zurueck", _groesste(r.diffs) <= SCHNITT and _ende_ms(r.diffs) <= 450 and fk2 == gk,
				"größte Änderung %.1f, Ende %d ms, Auswahl %s (Herkunft %s)" % [_groesste(r.diffs), _ende_ms(r.diffs), fk2, gk])
		await wait(1.0)
	# Unterbereich Angebote, dann sortieren (Y) auf einer Karte.
	main.goto("shop", "entdecken")
	await wait(2.0)
	r = await _aufn("s06_unterbereich_rb", func() -> void: Nav._fire("rb"), 40, [], Rect2(), 450, w_shop)
	await wait(2.0)
	var karte: Control = null
	for c in Nav.focusables(shop):
		if str(c.get_meta("uz_key", "")).begins_with("shop:") and str(c.get_meta("uz_key", "")) != "shop:hero":
			karte = c
			break
	if karte:
		Nav.focus(karte, true)
		await wait(1.0)
		var t0 := _toast_n()
		r = await _aufn("s07_sortieren_y", func() -> void: Nav._fire("y"), 40, [], Rect2(), 450, w_shop)
		var t1 := _toast_n()
		_e2("sortieren", _groesste(r.diffs) <= SCHNITT and t1 <= t0, "größte Änderung %.1f, Mitteilungen %d → %d, Hinweis Y: %s" % [
				_groesste(r.diffs), t0, t1, str(Nav.focused().get_meta("uz_hint_y", "")) if Nav.focused() else "-"])
		await wait(2.0)
	main.goto("shop", "entdecken")
	await wait(2.5)
	r = await _aufn("s10_shop_lt_spiele", func() -> void: Nav._fire("lt"), 40, [], Rect2(), 450)
	await wait(1.5)
	_e2("klang_launch", _launch.is_empty(), "„launch“ außerhalb des Spielstarts: %s" % (str(_launch) if not _launch.is_empty() else "nirgends"))


# --- Bereiche ---------------------------------------------------------------------------------

func _teil_bereiche() -> void:
	Config.set_value(AE.KEY, [])
	AE.add_store("4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App", "Netflix")
	AE.add_prog("C:\\Program Files\\Kodi\\kodi.exe", "Kodi")
	main.call("_rebuild")
	await wait(2.0)
	main.goto("games")
	await wait(2.0)
	await _waehle("g:", 1)
	await wait(0.8)
	main.goto("shop")
	await wait(2.5)
	var r := await _aufn("f01_freunde_rt", func() -> void: Nav._fire("rt"), 45, [], Rect2(), 450)
	_merke_launch("f01", r)
	await wait(2.0)
	# Freunde: ein Schritt in der Liste – die Karte bleibt, das Licht fällt nie ab.
	var fv: Control = main.friends_view()
	var fr := await _waehle("fr:")
	if fr:
		await wait(1.5)
		var licht: Array = []
		var w_licht := func() -> String:
			var g: Variant = fv.get("_k_glow")
			var a := (g as Control).modulate.a if g is Control and is_instance_valid(g) else -1.0
			licht.append(a)
			return "licht=%.3f" % a
		r = await _aufn("h05_freunde_runter", func() -> void: Nav._fire("down"), 40, [], Rect2(), 300, w_licht)
		var fall := 0.0
		for i in range(1, licht.size()):
			fall = maxf(fall, float(licht[0]) - float(licht[i]))
		# Der Inhalt der Karte (Änderung ≥ 1 je Bild) ist nach 300 ms fertig; das Licht wandert
		# danach gewollt langsam (T_LICHT) zur Farbe der Person weiter und fällt nie ab.
		var inhalt := 0
		for i in range(1, r.diffs.size()):
			if float(r.diffs[i]) >= 1.0:
				inhalt = roundi(i * 1000.0 / 60.0)
		_e2("freunde_schritt", inhalt <= 300 and fall <= 0.001 and float(licht[0]) > 0.0,
				"Inhalt fertig bei %d ms (Licht wandert bis %d ms), Licht %.2f, fällt höchstens um %.3f" % [inhalt, _ende_ms(r.diffs), float(licht[0]), fall])
		await wait(1.0)
		await _waehle("fr:")
		r = await _aufn("f02_freund_profil_auf", func() -> void: Nav._fire("y"), 50)
		_merke_launch("f02", r)
		var kl := _alle_klaenge(r)
		_e2("freund_profil_klang", not kl.contains("select") or kl.contains("select @17 ms (ersetzt"), "Klang: %s" % kl)
		await wait(2.0)
		await _aufn("f03_freund_profil_zu", func() -> void: Nav._fire("b"), 36)
		await wait(1.5)
	else:
		_notiz("kein Freund")
	# Profil: nach dem Laden springt nichts.
	r = await _aufn("f04_profil_rt", func() -> void: Nav._fire("rt"), 60, [], Rect2(), 450)
	_e2("profil_ruhig", _groesste(r.diffs, 18) <= 5.0, "größte Änderung nach 300 ms: %.2f (≤ 5)" % _groesste(r.diffs, 18))
	await wait(2.5)
	r = await _aufn("a01_apps_rt", func() -> void: Nav._fire("rt"), 45, [], Rect2(), 450)
	await wait(2.5)
	var schritte := 0
	while schritte < 8 and not AE.is_ext_id(str(main.current)):
		Nav._fire("rb")
		await wait(1.2)
		schritte += 1
	if AE.is_ext_id(str(main.current)):
		r = await _aufn("a02_eigene_app_rb", func() -> void: Nav._fire("rb"), 40)
		_e2("app_wechsel", _ende_ms(r.diffs) <= 450, "Ende %d ms" % _ende_ms(r.diffs))
		await wait(1.5)
		await _aufn("a03_eigene_app_lb", func() -> void: Nav._fire("lb"), 40)
		await wait(1.5)
	# Medien-Kacheln: Lichtstreif nur, wo das Theme ihn will; der neue Cursor im ersten Bild ≥ 0,7.
	await _kachel_takt("media:", "Medien-Kachel")
	main.goto("movies")
	await wait(3.0)
	await _kachel_takt("m:", "Film")
	if await _waehle("m:", 0, "poster"):
		r = await _aufn("m01_film_auf", func() -> void: Nav._fire("a"), 50)
		_merke_launch("m01", r)
		await wait(2.0)
		await _aufn("m02_film_zu", func() -> void: Nav._fire("b"), 36)
		await wait(1.5)
	main.goto("videos")
	await wait(3.0)
	await _kachel_takt("v:", "Video")
	if await _waehle("v:"):
		r = await _aufn("v01_video_auf", func() -> void: Nav._fire("a"), 50)
		_merke_launch("v01", r)
		await wait(2.0)
		await _aufn("v02_video_zu", func() -> void: Nav._fire("b"), 36)
		await wait(1.5)
	main.goto("music")
	await wait(3.0)
	await _kachel_takt("mt:", "Musik-Kachel")
	r = await _aufn("mu03_musik_rb", func() -> void: Nav._fire("rb"), 40)
	await wait(1.5)
	Config.set_value(AE.KEY, [])
	_e2("klang_launch", _launch.is_empty(), "„launch“ außerhalb des Spielstarts: %s" % (str(_launch) if not _launch.is_empty() else "nirgends"))


## Rechts auf die nächste Kachel dieser Art: Stand des neuen Rings im ersten Bild und ob ein
## Lichtstreif läuft (Graphit: focus.shine = false).
func _kachel_takt(prefix: String, was: String) -> void:
	var sec: Node = main.sections.get(main.current)
	var root: Control = sec if sec else main
	var treffer: Array = []
	var andere: Control = null
	for c in Nav.focusables(root):
		if str(c.get_meta("uz_key", "")).begins_with(prefix) and "_focus_t" in c:
			treffer.append(c)
		elif andere == null:
			andere = c
	if treffer.is_empty():
		_notiz("%s: keine Kachel" % was)
		return
	# Ziel: die zweite Kachel (von der ersten aus), sonst die eine (von etwas anderem aus).
	var b: Control = treffer[1] if treffer.size() > 1 else treffer[0]
	var a: Control = treffer[0] if treffer.size() > 1 else andere
	if a == null:
		a = main.get("tabs_box").get_child(0) if main.get("tabs_box") else null
	if a == null:
		_notiz("%s: nichts zum Wechseln davor" % was)
		return
	Nav.focus(a, true)
	await wait(0.8)
	Nav.focus(b, true)
	await RenderingServer.frame_post_draw
	var t1 := float(b.get("_focus_t"))
	await wait(0.5)
	var streif := 0
	for n in b.find_children("*", "Control", true, false):
		if n.get_script() and str(n.get_script().resource_path).ends_with("shine.gd") and (n as Control).is_visible_in_tree():
			streif += 1
	var will := UzTheme.focus_shine()
	_e2("takt_" + prefix.trim_suffix(":"), t1 >= 0.7 and (will or streif == 0),
			"%s: neuer Ring im ersten Bild %.2f (≥ 0,7), Lichtstreif %d (Theme will %s)" % [was, t1, streif, "ja" if will else "nein"])


# --- System -----------------------------------------------------------------------------------

func _teil_system() -> void:
	main.goto("games")
	await wait(2.0)
	await _waehle("g:", 1)
	await wait(0.8)
	await _aufn("k01_tastatur_auf", func() -> void: main.open_keyboard("Suchen", "", func(_q: String) -> void: pass), 40)
	await wait(1.0)
	await _aufn("k02_taste_a", func() -> void: Nav._fire("a"), 24)
	await wait(0.6)
	await _aufn("k03_tastatur_zu", func() -> void: Nav._fire("b"), 30)
	await wait(1.2)
	Toasts.show_toast("44nesq44 ist online", "Spielt gerade Hades II", "friends", {})
	await wait(0.4)
	Toasts.show_toast("Download fertig", "Hades II ist bereit", "download", {})
	await wait(7.0)
	await _aufn("n01_mitteilungen_auf", func() -> void: main.open_notifications(), 40)
	await wait(1.0)
	await _aufn("n03_mitteilungen_zu", func() -> void: Nav._fire("b"), 30)
	await wait(1.2)
	await _aufn("w01_neu_auf", func() -> void: WhatsNewL.open_for(main), 60, [0, 1, 2, 3, 4, 6, 9, 12, 18, 24, 30, 36, 48, 60], Rect2(), 450)
	await wait(1.5)
	await _aufn("w02_neu_zu", func() -> void: Nav._fire("b"), 30)
	await wait(1.2)
	await _aufn("o01_ausschalten_auf", func() -> void: main.open_power(), 45, [], Rect2(), 450)
	await wait(1.2)
	await _aufn("o02_ruhemodus_a", func() -> void: Nav._fire("a"), 60, [], Rect2(), 700)
	await wait(2.0)
	var t0 := _toast_n()
	var r := await _aufn("o03_aufwecken", func() -> void: Nav._fire("a"), 60, [], Rect2(), 700)
	await wait(1.0)
	var kl := _alle_klaenge(r)
	var t1 := _toast_n()
	_e2("aufwachen", not kl.contains("guide") and t1 <= t0, "Klang: %s; Mitteilungen %d → %d" % [kl if kl != "" else "keiner", t0, t1])
	await wait(3.0)
	await _schliessen()
	await _aufn("o04_ausschalt_animation", func() -> void: main.power_off("sleep", true), 100,
			[0, 6, 12, 18, 24, 33, 40, 48, 54, 60, 66, 72, 80, 90, 100], Rect2(), 1700)
	await wait(1.0)
	r = await _aufn("o05_wieder_an", func() -> void: main.power_on_again(), 45, [], Rect2(), 700)
	_e2("wieder_an", _groesste(r.diffs) <= SCHNITT, "größte Änderung in einem Bild %.1f (≤ %.0f)" % [_groesste(r.diffs), SCHNITT])
	await wait(1.5)
	await _aufn("e01_einrichtung_auf", func() -> void: Wizard.open_for(main, true), 50, [], Rect2(), 900)
	await wait(1.5)
	r = await _aufn("e02_schritt_weiter", func() -> void: Nav._fire("a"), 45, [], Rect2(), 450)
	_e2("einrichtung_weiter", _ende_ms(r.diffs) <= 450, "Ende %d ms" % _ende_ms(r.diffs))
	await wait(1.5)
	r = await _aufn("e03_schritt_zurueck", func() -> void: Nav._fire("b"), 45, [], Rect2(), 450)
	_e2("einrichtung_zurueck", _ende_ms(r.diffs) <= 450, "Ende %d ms" % _ende_ms(r.diffs))
	await wait(1.5)
	# „Fertig“: die Oberfläche kommt ohne Skalieren (höchstens die Tiefe der Ebenen, 98,5 %).
	var wz: Node = Nav.top_layer()
	var shell: Control = main.get("shell")
	var tief := [1.0]
	var w_sk := func() -> String:
		if is_instance_valid(shell):
			tief[0] = minf(tief[0], shell.scale.x)
		return "shell=%.3f" % (shell.scale.x if is_instance_valid(shell) else -1.0)
	if wz and wz.has_method("_finish"):
		r = await _aufn("e04_einrichtung_fertig", func() -> void: wz.call("_finish"), 50, [], Rect2(), 700, w_sk)
		_e2("einrichtung_fertig", float(tief[0]) >= 0.984 and _alle_klaenge(r).contains("boot") and not _alle_klaenge(r).contains("launch"),
				"kleinste Skalierung der Oberfläche %.3f (≥ 0,985), Klang: %s" % [float(tief[0]), _alle_klaenge(r)])
	await wait(1.5)
	await _schliessen()


# --- Halten -----------------------------------------------------------------------------------

func _teil_halten() -> void:
	main.goto("games")
	await wait(2.0)
	main.goto("videos")
	await wait(3.0)
	await _waehle("v:")
	await wait(1.0)
	var vv: Control = main.sections.get("videos")
	await _aufn("h01_videos_runter", func() -> void: Nav._fire("down"), 30, [], Rect2(), 450,
			func() -> String: return "y=%.1f" % _lage(vv, "_rows_box"))
	await wait(1.0)
	await _halte("h02_videos_halten", "down", 120, vv, "_rows_box")
	await wait(1.5)
	main.goto("movies")
	await wait(3.0)
	await _waehle("m:", 0, "poster")
	await wait(1.0)
	await _halte("h03_filme_halten", "down", 120, main.sections.get("movies"), "_rows_box")
	await wait(1.5)
	main.goto("music")
	await wait(3.0)
	var mt := _such("mt:", main.sections.get("music"))
	if mt:
		Nav.focus(mt, true)
		await wait(1.0)
		await _halte("h04_musik_halten", "down", 120, main.sections.get("music"), "_snap_col")
		await wait(1.5)


func _lage(sec: Node, feld: String) -> float:
	if sec == null:
		return 0.0
	var n: Variant = sec.get(feld)
	if n is Control and is_instance_valid(n):
		return (n as Control).position.y
	return 0.0


## Lage der Liste (Feld der Bereichs, sonst die erste rollende Liste) je Bild beim Halten; Tempo im
## gleichmäßigen Teil (ab dem 4. Schritt) als Verhältnis schnellstes : langsamstes Bild.
func _halte(name: String, d: String, n: int, sec: Node, feld: String) -> void:
	var sc: ScrollContainer = null
	if feld == "" and sec:
		for c in sec.find_children("*", "ScrollContainer", true, false):
			if (c as ScrollContainer).is_visible_in_tree() and (c as ScrollContainer).get_v_scroll_bar().max_value > (c as Control).size.y:
				sc = c
				break
	var lage := func() -> float:
		if sc and is_instance_valid(sc):
			return -float(sc.get_v_scroll_bar().value)
		return _lage(sec, feld)
	var ys: Array = []
	var wechsel: Array = []
	var prev := Nav.focused()
	var down := InputEventAction.new()
	down.action = "uz_" + d
	down.pressed = true
	await RenderingServer.frame_post_draw
	ys.append(float(lage.call()))
	Input.parse_input_event(down)
	for i in n:
		await RenderingServer.frame_post_draw
		ys.append(float(lage.call()))
		if Nav.focused() != prev:
			prev = Nav.focused()
			wechsel.append(i + 1)
	var up := InputEventAction.new()
	up.action = "uz_" + d
	up.pressed = false
	Input.parse_input_event(up)
	var v: Array = []
	var von: int = int(wechsel[3]) if wechsel.size() > 6 else 40
	var bis: int = int(wechsel[wechsel.size() - 1]) if wechsel.size() > 6 else ys.size() - 1
	for i in range(maxi(von, 1), mini(bis, ys.size())):
		v.append(absf(float(ys[i]) - float(ys[i - 1])))
	var lo := INF
	var hi := 0.0
	var stand := 0
	for x in v:
		lo = minf(lo, float(x))
		hi = maxf(hi, float(x))
		if float(x) < 0.5:
			stand += 1
	var ratio := hi / maxf(lo, 0.5) if not v.is_empty() else INF
	var line := "%s: Schritte bei Bild %s; Tempo zwischen 4. und letztem Schritt %.1f … %.1f px/Bild (%d Bilder, davon %d fast still), Verhältnis %.1f : 1" % [
		name, str(wechsel), lo if lo < INF else 0.0, hi, v.size(), stand, ratio]
	_sum.append(line)
	_abnahme.append("%s %s" % ["ok   " if ratio < 1.4 and stand == 0 else "FEHLT", line])
	var dir := out.path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("lage.csv"), FileAccess.WRITE)
	var rows := ["bild;ms;y"]
	for i in ys.size():
		rows.append("%d;%d;%.2f" % [i, roundi(i * 1000.0 / 60.0), float(ys[i])])
	f.store_string("\n".join(rows) + "\n")
	f.close()
	print(line)

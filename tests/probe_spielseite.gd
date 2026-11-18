extends "res://tests/probe_base.gd"
## Probe für die Spielseite: Kopf mit Pillen, „Fast geschafft“, Neuigkeiten mit Patchnotes, Erweiterungen,
## Bewertungen und der Soundtrack-Knopf (Elden Ring aus der Demo-Bibliothek). Neuigkeiten und
## Erweiterungen kommen aus tests/fixtures/spielseite bzw. Beispielen, weil die Demo dafür nichts hat.


func run() -> void:
	var appid := 1245620
	Store._news[appid] = Store.parse_news(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/spielseite/news.json")), 3)
	var dlc: Array = []
	for d in [[2778580, "ELDEN RING Shadow of the Erdtree", 3999], [2778590, "ELDEN RING Nightreign – Vorbestellerbonus", 0],
			[9990000, "Digitales Artbook & Soundtrack", 999]]:
		dlc.append({ "appid": d[0], "name": d[1], "price": d[2], "original": d[2], "discount": 0,
			"header": Store.CDN % [d[0], "header.jpg"], "capsule": Store.CDN % [d[0], "capsule_616x353.jpg"] })
	Store._dlc[appid] = dlc
	var g := Library.get_game("steam:%d" % appid)
	main.open_game(g)
	await shot("01_oben", 2.0)
	# Pille „Erfolge“ unter den Knöpfen gewählt (leiser Schein statt Rahmen).
	var pille := _find_key("gp:k:erfolge")
	if pille:
		Nav.focus(pille, true)
		await shot("01b_pille", 0.6)
	# Soundtrack-Knopf in der Knopfreihe (rechts außen), dann zurück auf „Spielen“
	Nav.focus(_find_key("gp:ost"), true)
	await shot("02_soundtrack_knopf", 0.5)
	await press("left", 4)
	await press("down")
	await shot("03_bilder", 0.8)
	await press("down")
	await shot("04_erfolge", 0.8)
	await press("down")
	await shot("05_fast_geschafft", 0.9)
	await press("down")
	await shot("06_naechster", 0.9)
	await press("down")
	await shot("07_naechster", 0.9)
	await press("down")
	await shot("08_naechster", 0.9)
	await press("down")
	await shot("09_naechster", 0.9)
	await press("down")
	await shot("10_naechster", 0.9)
	# Ganz unten, dann zurück zu den Neuigkeiten und eine lesen.
	var nf := _find_key("gp:news:0")
	if nf:
		Nav.focus(nf, true)
		await shot("11_neuigkeiten", 0.9)
		await press("a")
		await shot("12_patchnotes_lesen", 1.0)
		await press("b")
		await wait(0.6)
	var rf := _find_key("gp:rv")
	if rf:
		Nav.focus(rf, true)
		await shot("13_bewertungen", 0.9)
	var df := _find_key("shop:2778580")
	if df:
		Nav.focus(df, true)
		await shot("14_erweiterungen", 0.9)
		await press("a")
		await shot("15_erweiterung_shop", 2.0)
		await press("b")
		await wait(0.6)
	var ost := _find_key("gp:ost")
	if ost:
		Nav.focus(ost, true)
		await wait(0.4)
		await press("a")
		await shot("16_soundtrack_suche", 2.0)
		await press("b")
		await wait(0.6)
	print("Abschnitte: news=%s rv=%s dlc=%s ost=%s almost=%s" % [nf != null, rf != null, df != null, ost != null, _find_key("gp:almost:0") != null])


func _find_key(key: String) -> Control:
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control and n.has_meta("uz_key") and str(n.get_meta("uz_key")) == key and (n as Control).is_visible_in_tree():
			return n
		stack.append_array(n.get_children())
	return null

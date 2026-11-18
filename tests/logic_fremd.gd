extends Node
## Werte fremder Herkunft lesen (src/core/fremd.gd) und die Antworten von Net: null heißt „fehlt“.
## Ohne Netz. Aufruf: godot --headless --path . res://tests/logic_fremd.tscn

const Fremd := preload("res://src/core/fremd.gd")

var fails := 0
var _marke := false      ## „lädt“-Marke für die Probe unten


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _fremder_wert(v: Variant) -> Variant:
	return v


## Bricht mit einem Skriptfehler ab (int(null)), sofort oder nach einem Warten.
func _bricht_ab(erst_warten: bool) -> bool:
	if erst_warten:
		await get_tree().process_frame
	var n := int(_fremder_wert(null))
	return n == 0


func _ready() -> void:
	print("JSON lesen")
	var d: Variant = Fremd.json('{"a": null, "b": 3, "c": {"d": null, "e": [null, {"f": null, "g": 1}]}, "h": []}')
	check(d is Dictionary and not d.has("a") and d.b == 3.0, "null im Verzeichnis fällt weg, der Rest bleibt")
	check(not d.c.has("d") and (d.c.e as Array).size() == 2 and d.c.e[0] == null, "auch in der Tiefe; Listen behalten ihre Plätze")
	check(not d.c.e[1].has("f") and d.c.e[1].g == 1.0 and d.h == [], "Verzeichnis in einer Liste wird gesäubert")
	check(Fremd.json("") == null and Fremd.json("{kaputt") == null and Fremd.json("null") == null, "leer, kaputt, nur null: nichts")
	check(Fremd.json("[1, null]") == [1.0, null] and Fremd.json('"text"') == "text", "Liste und Text an der Wurzel bleiben")
	# Genau der Fall, um den es geht: Der Ersatzwert greift jetzt.
	check(int(d.get("a", 7)) == 7 and bool(d.c.get("d", true)) and (d.get("a", []) as Array).is_empty(), "get() mit Ersatzwert trifft null nicht mehr")
	var tief: Variant = {}
	var cur: Dictionary = tief
	for i in 200:
		cur["n"] = { "x": null }
		cur = cur["n"]
	check(Fremd.ohne_null(tief) is Dictionary, "sehr tiefe Schachtelung bricht nicht ab")

	print("Art prüfen")
	check(Fremd.verz([]) == {} and Fremd.verz(null) == {} and Fremd.verz("x") == {} and Fremd.verz({ "a": 1 }) == { "a": 1 }, "Verzeichnis oder leer")
	check(Fremd.liste({}) == [] and Fremd.liste(null) == [] and Fremd.liste(3) == [] and Fremd.liste([1]) == [1], "Liste oder leer")
	check(Fremd.zahl(5) == 5 and Fremd.zahl(5.9) == 5 and Fremd.zahl("42") == 42 and Fremd.zahl(" -7 ") == -7 and Fremd.zahl("3.0") == 3,
			"Zahl aus Zahl und Ziffern-Text")
	check(Fremd.zahl(null, 9) == 9 and Fremd.zahl("abc", 9) == 9 and Fremd.zahl([], 9) == 9 and Fremd.zahl({}, 9) == 9 and Fremd.zahl(true, 9) == 9,
			"nichts, Text, Liste, Verzeichnis, Schalter: der Ersatzwert")
	check(Fremd.zahl(INF, 1) == 1 and Fremd.zahl(NAN, 1) == 1 and Fremd.zahl(1.0e30, 1) == 1 and Fremd.zahl("1e400", 1) == 1,
			"unendlich, NaN und zu groß zählen nicht")
	check(Fremd.komma("1.5") == 1.5 and Fremd.komma(2) == 2.0 and Fremd.komma(null, 0.5) == 0.5 and Fremd.komma(NAN, 0.5) == 0.5 and Fremd.komma("x",
			0.5) == 0.5,
			"Kommazahl oder Ersatzwert")
	check(Fremd.ja(true) and not Fremd.ja(false) and Fremd.ja(1) and not Fremd.ja(0) and Fremd.ja("true") and Fremd.ja("1"),
			"Schalter aus Schalter, Zahl, „1“ und „true“")
	check(not Fremd.ja(null) and not Fremd.ja("ja") and not Fremd.ja([]) and not Fremd.ja({}) and not Fremd.ja("false"), "alles andere ist falsch")
	check(Fremd.text("a") == "a" and Fremd.text(3) == "3" and Fremd.text(3.0) == "3" and Fremd.text(2.5) == "2.5", "Text aus Text und Zahl")
	check(Fremd.text(null) == "" and Fremd.text([], "–") == "–" and Fremd.text({}) == "" and Fremd.text(true) == "" and Fremd.text("abcdef", "", 3) == "abc",
			"nichts, Liste, Verzeichnis, Schalter: Ersatzwert; Länge begrenzt")

	print("Weg durch eine Antwort")
	var r := { "game": { "stats": { "liste": [{ "id": 4 }, "x"] }, "leer": [] }, "n": null }
	check(Fremd.weg(r, "game/stats/liste/0/id") == 4 and Fremd.weg(r, "game/stats/liste/1") == "x", "Schlüssel und Listenplätze")
	check(Fremd.weg(r, "game/fehlt/x") == null and Fremd.weg(r, "game/stats/liste/5", "–") == "–" and Fremd.weg(r, "game/stats/liste/-1") == null,
			"fehlender Schlüssel, Platz außerhalb: Ersatzwert")
	check(Fremd.weg(r, "game/leer/stats") == null and Fremd.weg(r, "game/stats/liste/1/id") == null and Fremd.weg(null, "a") == null and Fremd.weg("x",
			"a", 0) == 0,
			"Liste statt Verzeichnis, Text statt Verzeichnis, nichts: Ersatzwert statt Fehler")
	check(Fremd.weg(r, "n", 5) == 5 and Fremd.liste(Fremd.weg(r, "game/leer")).is_empty() and Fremd.verz(Fremd.weg(r, "game/stats")).has("liste"),
			"null am Ziel: Ersatzwert")
	check(Fremd.verz(r, "game/stats").has("liste") and Fremd.verz(r, "game/leer") == {} and Fremd.verz(r, "fehlt") == {} and Fremd.verz("x", "a") == {},
			"Verzeichnis unter einem Weg, sonst leer")
	check(Fremd.liste(r, "game/stats/liste").size() == 2 and Fremd.liste(r, "game/stats") == [] and Fremd.liste(null, "a") == [],
			"Liste unter einem Weg, sonst leer")
	check(Fremd.zeilen(r, "game/stats/liste") == [{ "id": 4 }] and Fremd.zeilen([null, { "a": 1 }, "x", 3, [], { "b": 2 }]) == [{ "a": 1 }, { "b": 2 }],
			"Liste von Einträgen: nur die Verzeichnisse")
	var rein := [{ "a": 1 }, { "b": 2 }]
	check(is_same(Fremd.zeilen(rein), rein) and Fremd.zeilen({ "a": 1 }) == [] and Fremd.zeilen("text") == [] and Fremd.zeilen(r, "game/fehlt") == [],
			"saubere Liste bleibt dieselbe (keine Kopie); Verzeichnis oder Text statt Liste: leer")

	print("Steuerzeichen und Schreibrichtung in fremden Texten")
	var rlo := String.chr(0x202E)
	check(Fremd.sauber("A" + rlo + "B" + String.chr(1) + "C\tD\nE" + String.chr(0x85) + "F" + String.chr(0x2067) + "Gä€") == "ABC\tD\nEFGä€",
			"sauber: Steuerzeichen und Richtungswechsel raus, Tabulator, Umbruch und alles andere bleiben")
	var js1: Variant = Fremd.json('{"name": "Mira\\u202Egnp.exe", "liste": ["a\\u0001b", {"t": "x\\u2066y", "n": 3}], "ok": "Zeile 1\\nZeile 2\\tT", "z": 5}')
	check(js1 is Dictionary and js1.name == "Miragnp.exe" and js1.liste[0] == "ab" and js1.liste[1].t == "xy" and int(js1.liste[1].n) == 3
			and js1.ok == "Zeile 1\nZeile 2\tT" and int(js1.z) == 5, "JSON: Texte in jeder Tiefe gesäubert, Zahlen und Zeilenumbrüche bleiben")
	var js2: Variant = Fremd.json('{"name": "A' + rlo + 'B"}')
	check(js2 is Dictionary and js2.name == "AB", "JSON: roh geschriebene Zeichen ebenso")
	var js3: Variant = Fremd.json('{"a": "ä€ 日本 \\u00e4", "b": [1, 2]}')
	check(js3 is Dictionary and js3.a == "ä€ 日本 ä" and js3.b == [1.0, 2.0], "JSON ohne solche Zeichen bleibt, wie es ist")
	check(Fremd.anzeige("A\tB\nC" + rlo + "D", 5) == "A B C" and Fremd.anzeige("x") == "x", "anzeige: eine Zeile, gekürzt")

	print("Antworten von Net")
	var antwort := { "ok": true, "code": 200, "body": '{"daten": {"preis": null, "titel": "A"}, "fehler": null}'.to_utf8_buffer() }
	var klein: Dictionary = Net._decode(antwort)
	check(klein.data is Dictionary and not klein.data.has("fehler") and not klein.data.daten.has("preis") and klein.data.daten.titel == "A",
			"kleine Antwort: null heißt fehlt")
	var gross: Variant = Net.parse_json_now('{"a": null, "b": [{"c": null}]}'.to_utf8_buffer())
	check(gross is Dictionary and not gross.has("a") and not gross.b[0].has("c"), "große Antwort (Hintergrund): ebenso")
	check(Net.parse_json_now(PackedByteArray()) == null and Net._decode({ "ok": false, "code": 500, "body": "kein json".to_utf8_buffer() }).text == "kein json",
			"leer und Nicht-JSON wie bisher")

	print("Antworten des Windows-Helfers")
	# So schreibt der Helfer wirklich (PowerShell, ConvertTo-Json): bei Erfolg „error: null“, bei einem Fehler „result: null“.
	var gut: Dictionary = Helper.antwort(Fremd.json('{"ok":true,"id":1,"result":{"pong":true,"titel":null,"pid":7284},"error":null}'))
	check(gut.ok == true and gut.error == "" and gut.result == { "pong": true, "pid": 7284.0 }, "Erfolg: kein Fehlertext (vorher „<null>“), null im Ergebnis fehlt")
	var schlecht: Dictionary = Helper.antwort(Fremd.json('{"ok":false,"id":2,"result":null,"error":"Unbekannter Befehl: x"}'))
	check(schlecht.ok == false and schlecht.result == {} and schlecht.error == "Unbekannter Befehl: x", "Fehler: Ergebnis ist leer statt null, der Text bleibt")
	check(int(gut.result.get("pid", 0)) == 7284 and str(gut.result.get("titel", "–")) == "–" and str(schlecht.result.get("x", "")) == "",
			"Aufrufer lesen beides mit get() und Ersatzwert, ohne Fehler")
	var kaputt: Dictionary = Helper.antwort(null)
	check(kaputt.ok == false and kaputt.result == {} and kaputt.error == "" and Helper.antwort({ "ok": "ja", "error": 5 }).ok == false, "keine Antwort oder Unsinn: nicht ok")
	check(not Helper.klartext(str(gut.error)).contains("null"), "auf dem Bildschirm steht nie „null“")

	print("Abbruch in einer erwarteten Funktion")
	# Darauf bauen die Hüllen um alle Lade-Funktionen (Library.scan, Achievements.refresh_overview …): Bricht die
	# erwartete Funktion mit einem Skriptfehler ab, läuft der Aufrufer weiter und kann die Marke lösen. Ändert eine
	# spätere Godot-Fassung das, fällt es hier auf. (Die zwei Fehlermeldungen im Protokoll sind gewollt.)
	_marke = true
	var sofort: bool = await _bricht_ab(false)
	_marke = false
	check(sofort == false and not _marke, "Fehler vor dem ersten Warten: der Aufrufer läuft weiter, das Ergebnis ist der leere Wert")
	_marke = true
	var spaeter: bool = await _bricht_ab(true)
	_marke = false
	check(spaeter == false and not _marke, "Fehler nach einem Warten: ebenso")

	print("Tempo")
	var gruppe: Array = []
	for i in 400:
		gruppe.append({ "id": i, "name": "Eintrag %d" % i, "preis": null, "bilder": [{ "u": "a", "b": null }, { "u": "b" }], "tags": ["x", "y"],
				"mehr": { "k": null, "l": 1 } })
	var text := JSON.stringify({ "items": gruppe })
	var best := 1.0e9
	for _i in 5:
		var t0 := Time.get_ticks_usec()
		Fremd.json(text)
		best = minf(best, Time.get_ticks_usec() - t0)
	var nur := 1.0e9
	for _i in 5:
		var t0 := Time.get_ticks_usec()
		JSON.parse_string(text)
		nur = minf(nur, Time.get_ticks_usec() - t0)
	print("    %d KB: lesen %.1f ms, mit Säubern %.1f ms" % [text.length() / 1024, nur / 1000.0, best / 1000.0])
	check(best < 60000, "eine Antwort von %d KB in unter 60 ms" % (text.length() / 1024))

	print("Leiser Leser (json_roh)")
	var roh: Variant = Fremd.json_roh("{\"a\": null, \"b\": \"x\\u202ey\", \"c\": [1, null]}")
	check(roh is Dictionary and (roh as Dictionary).has("a") and roh["a"] == null and str(roh["b"]).length() == 3 and (roh["c"] as Array)[1] == null,
			"gültiger Text kommt unverändert an (null bleibt, nichts wird gesäubert)")
	check(Fremd.json_roh("") == null and Fremd.json_roh("{kaputt") == null and Fremd.json_roh("[1, 2") == null and Fremd.json_roh("3") == 3.0,
			"leer und kaputt ergeben null, ohne Fehlerzeile im Protokoll")
	# JSON.parse_string schreibt bei kaputtem Text je Aufruf einen Fehler samt Aufrufstapel ins Protokoll: in src/ nirgends mehr.
	var treffer: Array = []
	var offen := ["res://src"]
	while not offen.is_empty():
		var ordner: String = offen.pop_back()
		for unter in DirAccess.get_directories_at(ordner):
			offen.append(ordner.path_join(unter))
		for datei in DirAccess.get_files_at(ordner):
			if datei.ends_with(".gd") and FileAccess.get_file_as_string(ordner.path_join(datei)).contains("JSON.parse_" + "string("):
				treffer.append(datei)
	check(treffer.is_empty(), "kein JSON.parse_string mehr in src/ (%s)" % ", ".join(treffer))

	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)

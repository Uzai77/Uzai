extends Node
## Stil- und Sicherheitsregeln für den ganzen GDScript-Code (tools/lint_gd.py): Tabs, höchstens
## 160 Zeichen, nichts am Zeilenende, Kurzbeschreibung am Dateianfang, keine verbotenen Aufrufe
## auf fremden Daten. Erst prüft das Werkzeug seine Regeln an eigenen Beispielen, dann den Code.
## Aufruf: godot --headless --path . res://tests/logic_lint.tscn (braucht python3).

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	var tool := ProjectSettings.globalize_path("res://tools/lint_gd.py")
	print("Regeln am Beispiel")
	var out := _run([tool, "--selbsttest"])
	check(out.code == 0 and str(out.text).contains("Selbsttest: alles ok"), "Selbsttest des Werkzeugs")
	print("Ganzer Code")
	out = _run([tool])
	var last := str(out.text).strip_edges().get_slice("\n", str(out.text).strip_edges().get_slice_count("\n") - 1)
	check(out.code == 0 and last.contains("Fehler: 0"), "src/ und tests/ ohne Fehler (%s)" % last)
	if out.code != 0:
		for l in str(out.text).split("\n").slice(0, 20):
			print("       ", l)
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## python3 im abgeschotteten Modus (-I: keine Umgebung, kein Benutzer-Ordner); Ausgabe und Ende.
func _run(args: Array) -> Dictionary:
	var o: Array = []
	var code := OS.execute("python3", PackedStringArray(["-I"] + args), o, true)
	if code == -1:
		print("       python3 fehlt – ohne das Werkzeug lässt sich nichts prüfen")
	return { "code": code, "text": "".join(PackedStringArray(o)) }

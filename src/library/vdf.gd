extends RefCounted
## Liest das Textformat von Valve (KeyValues), in dem Steam seine Bibliotheksordner
## (libraryfolders.vdf) und installierten Spiele (appmanifest_*.acf) speichert.


static func parse(text: String) -> Dictionary:
	var tokens := _tokenize(text)
	var pos := [0]
	return _parse_block(tokens, pos)


static func parse_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return parse(FileAccess.get_file_as_string(path))


## Zerlegt den Text in einem Lauf der Engine statt Zeichen für Zeichen im Skript. Das alte Vorgehen hängte
## jedes Zeichen einzeln an: gemessen 2 s für einen Wert mit 200.000 Zeichen (die Zeit wuchs mit dem Quadrat
## der Länge) – eine kaputte Datei in Steams Ordner hätte Uzai anhalten können. Je Fundstelle: erst Leerraum und
## Kommentare (// bis zum Zeilenende), dann höchstens eine Gruppe: 1 = Klammer, 2 = Text in Anführungszeichen
## (mit Rückstrich-Folgen, auch ohne schließendes Zeichen am Ende), 3 = Wort ohne Anführungszeichen.
static var _RX_TOKEN := RegEx.create_from_string(
		"(?:[ \\t\\n\\r]++|//[^\\n]*+)*+(?:([{}])|\"((?:[^\"\\\\]++|\\\\[\\s\\S])*+\\\\?)\"?|([^ \\t\\n\\r{}\"]+))?")


static func _tokenize(text: String) -> Array:
	var out: Array = []
	for m in _RX_TOKEN.search_all(text):
		var teile := m.strings
		if teile[1] != "":
			out.append(teile[1])
		elif teile[3] != "":
			out.append(["s", teile[3]])
		elif m.get_start(2) >= 0:
			var q := teile[2]
			out.append(["s", _entwerten(q) if q.contains("\\") else q])
	return out


## Rückstrich-Folgen auflösen: \n und \t, sonst das Zeichen selbst; ein einzelner Rückstrich am Ende bleibt.
static func _entwerten(q: String) -> String:
	var out := ""
	var i := 0
	while true:
		var k := q.find("\\", i)
		if k < 0 or k + 1 >= q.length():
			return out + q.substr(i)
		var esc := q[k + 1]
		out += q.substr(i, k - i) + ("\n" if esc == "n" else ("\t" if esc == "t" else esc))
		i = k + 2
	return out


static func _parse_block(tokens: Array, pos: Array) -> Dictionary:
	var d := {}
	while pos[0] < tokens.size():
		var t: Variant = tokens[pos[0]]
		if t is String and t == "}":
			pos[0] += 1
			return d
		if not (t is Array):
			pos[0] += 1
			continue
		var key: String = t[1]
		pos[0] += 1
		if pos[0] >= tokens.size():
			break
		var v: Variant = tokens[pos[0]]
		if v is String and v == "{":
			pos[0] += 1
			d[key] = _parse_block(tokens, pos)
		elif v is Array:
			d[key] = v[1]
			pos[0] += 1
		else:
			pos[0] += 1
	return d


## Sucht einen Schlüssel ohne auf Groß-/Kleinschreibung zu achten (Steam ist da uneinheitlich).
static func get_ci(d: Dictionary, key: String, fallback: Variant = null) -> Variant:
	var low := key.to_lower()
	for k in d.keys():
		if str(k).to_lower() == low:
			return d[k]
	return fallback

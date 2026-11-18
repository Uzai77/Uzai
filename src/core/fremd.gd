extends RefCounted
## Werte fremder Herkunft lesen: Antworten von Diensten, Ausgaben fremder Programme, fremde Dateien.
## Ohne Zustand und ohne Netz (tests/logic_fremd.gd).
##
## Warum es das braucht: GDScript bricht eine Funktion mit einem Skriptfehler ab, wenn ein Wert nicht die
## erwartete Art hat – und der Ersatzwert von get() greift nur, wenn der Schlüssel fehlt, nicht wenn er
## null ist. Gemessen (Godot 4.5.1):
##   int(null), float(null), bool(null), bool("text"), int([])      → Skriptfehler
##   var l: Array = d.get("liste", [])  mit  "liste": null          → Skriptfehler
##   d.get("a", {}).get("b")  mit  "a": null  oder  "a": []         → Skriptfehler
##   "text" == true,  null < 3,  "5" > 3                            → Skriptfehler
## Wer auf die abgebrochene Funktion wartet (await), bekommt den Ersatzwert ihrer Rückgabeart – leer, 0, falsch –
## und rechnet damit weiter (gemessen, auch nach einem Abbruch mitten im Lauf). Marken und Zähler, die sie am
## Ende zurücksetzen wollte, bleiben stehen; wer auf die wartet, wartet für immer. Dienste schicken null
## alltäglich („Feld gibt es, Wert fehlt“), und PHP-Dienste schicken ein leeres Verzeichnis als leere Liste.
##
## Zwei Mittel:
##   1. json() und ohne_null(): null in einem Verzeichnis heißt „fehlt“. Danach greifen die Ersatzwerte
##      von get(). Net liest jede Antwort so (Net.get_json, send_json, post_form).
##   2. verz(), liste(), zeilen(), zahl(), komma(), ja(), text(), weg(): ein Wert in der erwarteten Art
##      oder der Ersatzwert, nie ein Fehler. Mit Weg lesen sie gleich durch die Antwort:
##          for p in Fremd.zeilen(r.data, "response/players"):

## Tiefer schachtelt keine Antwort, die Uzai liest; darunter bleibt alles, wie es ist.
const TIEFE_MAX := 64


## JSON-Text lesen. null, wenn er leer oder kaputt ist; null-Werte in Verzeichnissen fallen weg, und Texte kommen
## ohne Steuerzeichen und ohne Zeichen an, die die Schreibrichtung umdrehen (sauber()).
static func json(text: String) -> Variant:
	if text.is_empty():
		return null
	var js := JSON.new()
	if js.parse(text) != OK:
		return null
	var d: Variant = ohne_null(js.data)
	# In echten Antworten kommen solche Zeichen so gut wie nie vor: erst nachsehen (1 MB in 2,5 ms, gemessen), nur dann
	# die ganze Antwort durchgehen.
	return alles_sauber(d) if _VERDACHT.search(text) != null else d


## JSON-Text lesen, wie er ist: null, wenn er leer oder kaputt ist – sonst der Wert unverändert (null-Werte
## bleiben, Texte werden nicht gesäubert). Für Stellen, die jedes Feld selbst prüfen (Leitung des Browsers) oder
## eigene Dateien lesen. Anders als JSON.parse_string schreibt das bei kaputtem Text nichts ins Protokoll: Dort
## stünde sonst je Eingabe eine Fehlerzeile samt Aufrufstapel (gemessen) – bei fremdem Text ließe sich das
## Protokoll so fluten.
static func json_roh(text: String) -> Variant:
	if text.is_empty():
		return null
	var js := JSON.new()
	return js.data if js.parse(text) == OK else null


## Steuerzeichen (außer Tabulator und Zeilenumbruch) und Zeichen, die die Schreibrichtung umdrehen oder einbetten.
## Namen, Titel und Nachrichten schreiben Fremde: Mit umgedrehter Schreibrichtung steht auf dem Bildschirm etwas
## anderes als im Text (ein Name, ein Link), Steuerzeichen haben in einer Beschriftung nichts verloren.
## Das Nullzeichen ersetzt schon Godots JSON-Leser (gemessen).
static var _UNSICHTBAR := RegEx.create_from_string("[\\x{00}-\\x{08}\\x{0B}\\x{0C}\\x{0E}-\\x{1F}\\x{7F}-\\x{9F}\\x{202A}-\\x{202E}\\x{2066}-\\x{2069}]")
## Dieselben in einem JSON-Text: roh oder als „\uXXXX“ geschrieben (zum schnellen Nachsehen vor dem Säubern).
static var _VERDACHT := RegEx.create_from_string(
		"[\\x{7F}-\\x{9F}\\x{202A}-\\x{202E}\\x{2066}-\\x{2069}]|\\\\u(00[01][0-9a-fA-F]|007[fF]|00[89][0-9a-fA-F]|202[a-eA-E]|206[6-9])")


## Ein fremder Text ohne diese Zeichen (Tabulator und Zeilenumbruch bleiben).
static func sauber(s: String) -> String:
	return _UNSICHTBAR.sub(s, "", true)


## Alle Texte einer gelesenen Antwort säubern (am Wert selbst, auch in der Tiefe). Schlüssel bleiben, wie sie sind.
static func alles_sauber(v: Variant, tiefe := 0) -> Variant:
	if v is String:
		return sauber(v)
	if tiefe > TIEFE_MAX:
		return v
	if v is Dictionary:
		var d: Dictionary = v
		for k in d:
			var w: Variant = d[k]
			if w is String or w is Dictionary or w is Array:
				d[k] = alles_sauber(w, tiefe + 1)
	elif v is Array:
		var a: Array = v
		for i in a.size():
			var w: Variant = a[i]
			if w is String or w is Dictionary or w is Array:
				a[i] = alles_sauber(w, tiefe + 1)
	return v


## Einträge mit dem Wert null aus allen Verzeichnissen nehmen (am Wert selbst, auch in der Tiefe). Listen
## behalten ihre Plätze: Dort kann die Stelle etwas bedeuten, wer Listen liest, prüft jeden Eintrag.
static func ohne_null(v: Variant, tiefe := 0) -> Variant:
	if tiefe > TIEFE_MAX:
		return v
	if v is Dictionary:
		var d: Dictionary = v
		var weg_damit: Array = []
		for k in d:
			var w: Variant = d[k]
			if w == null:
				weg_damit.append(k)
			elif w is Dictionary or w is Array:
				ohne_null(w, tiefe + 1)
		for k in weg_damit:
			d.erase(k)
	elif v is Array:
		for w in (v as Array):
			if w is Dictionary or w is Array:
				ohne_null(w, tiefe + 1)
	return v


## Verzeichnis (mit pfad: das unter diesem Weg), sonst leer.
static func verz(v: Variant, pfad := "") -> Dictionary:
	var w: Variant = v if pfad == "" else weg(v, pfad)
	return w if w is Dictionary else {}


## Liste (mit pfad: die unter diesem Weg), sonst leer.
static func liste(v: Variant, pfad := "") -> Array:
	var w: Variant = v if pfad == "" else weg(v, pfad)
	return w if w is Array else []


## Die übliche Form „Liste von Einträgen“: nur die Verzeichnisse einer Liste, alles andere fällt weg
## (null mitten in der Liste, eine Fehlermeldung als Text). Mit pfad: die Liste unter diesem Weg.
static func zeilen(v: Variant, pfad := "") -> Array:
	var l := liste(v, pfad)
	for e in l:
		if not (e is Dictionary):
			return l.filter(func(x: Variant) -> bool: return x is Dictionary)
	return l


## Ganze Zahl aus Zahl oder Ziffern-Text („42“, „-7“, „3.0“), sonst der Ersatzwert. Unendlich und NaN
## zählen nicht (int() machte daraus die kleinste Zahl).
static func zahl(v: Variant, std := 0) -> int:
	if v is int:
		return v
	if v is float:
		return int(v) if is_finite(v) and absf(v) < 9.0e18 else std
	if v is String and (v as String).length() <= 24 and (v as String).strip_edges().is_valid_float():
		var f := (v as String).strip_edges().to_float()
		return int(f) if is_finite(f) and absf(f) < 9.0e18 else std
	return std


## Kommazahl aus Zahl oder Zahlen-Text, sonst der Ersatzwert.
static func komma(v: Variant, std := 0.0) -> float:
	if v is int:
		return float(v)
	if v is float:
		return v if is_finite(v) else std
	if v is String and (v as String).length() <= 32 and (v as String).strip_edges().is_valid_float():
		var f := (v as String).strip_edges().to_float()
		return f if is_finite(f) else std
	return std


## Wahr oder falsch: ein Schalter, eine Zahl ungleich null, oder „1“/„true“ als Text. Alles andere ist falsch.
static func ja(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return v is String and (v as String).to_lower() in ["1", "true"]


## Text aus Text oder Zahl (ganze Kommazahlen ohne „.0“), sonst der Ersatzwert. laenge > 0 kürzt.
static func text(v: Variant, std := "", laenge := 0) -> String:
	var s := std
	if v is String:
		s = v
	elif v is int:
		s = str(v)
	elif v is float:
		s = str(int(v)) if is_finite(v) and v == floorf(v) and absf(v) < 9.0e15 else str(v)
	return s.left(laenge) if laenge > 0 else s


## Wert unter einem Weg („game/stats/achievements“, Listenplätze als Zahl: „data/0/id“). Führt der Weg
## nicht dorthin (Schlüssel fehlt, falsche Art, Platz gibt es nicht), der Ersatzwert.
static func weg(v: Variant, pfad: String, std: Variant = null) -> Variant:
	var cur: Variant = v
	for teil in pfad.split("/"):
		if cur is Dictionary:
			if not (cur as Dictionary).has(teil):
				return std
			cur = cur[teil]
		elif cur is Array and teil.is_valid_int():
			var i := int(teil)
			if i < 0 or i >= (cur as Array).size():
				return std
			cur = cur[i]
		else:
			return std
	return std if cur == null else cur


## Zeichen zu einer Nummer aus „&#…;“ in fremdem Text (Titel, Profiltexte). Steuerzeichen – auch das Nullzeichen, an
## dem ein Text endet –, Zeichen, die die Schreibrichtung umdrehen, und Nummern außerhalb von Unicode fallen weg.
static func zeichen(n: int) -> String:
	if n == 10:
		return "\n"
	if n == 9:
		return " "
	if n < 32 or n == 127 or (n >= 0x80 and n < 0xA0) or (n >= 0x202A and n <= 0x202E) or (n >= 0x2066 and n <= 0x2069) \
			or (n >= 0xD800 and n <= 0xDFFF) or n > 0x10FFFF:
		return ""
	return String.chr(n)


## Fremder Text zum Anzeigen (Titel und Beschreibung einer fremden Seite): ohne Steuerzeichen und ohne Zeichen, die
## die Schreibrichtung umdrehen; Tabulator und Zeilenumbruch werden Leerzeichen. laenge > 0 kürzt.
static func anzeige(s: String, laenge := 0) -> String:
	var out := sauber(s).replace("\t", " ").replace("\r", " ").replace("\n", " ")
	return out.left(laenge) if laenge > 0 else out

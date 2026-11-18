extends RefCounted
## Treffer für die globale Suche (Punkt 105): Wie gut passt ein Suchwort zu einem Namen? Verzeiht,
## was man mit dem Controller oder einer fremden Tastatur so tippt: Groß/klein, Umlaute als „ue“
## oder ohne Punkte, Akzente („Okami“ für „Ōkami“), Satzzeichen, Wörter in anderer Reihenfolge,
## Anfangsbuchstaben („gta“), römische Zahlen („ff 7“ für „Final Fantasy VII“) und einen
## Tippfehler je Wort. Läuft lokal und ohne Netz; getestet in tests/logic_suche.gd.

const EXACT := 1000
const PREFIX := 900
const WORD_PREFIX := 800
const ALL_WORDS := 700
const INITIALS := 620
const INSIDE := 500
const TYPO := 320
const MIN_TYPO_LEN := 4           ## kürzere Wörter müssen stimmen (sonst passt fast alles)

## Zeichen, die beim Vergleichen gleich gelten. Umlaute einmal ohne Punkte – die zweite Schreibweise
## („ue“) kommt in variants() dazu.
const FOLD := {
	"ä": "a", "ö": "o", "ü": "u", "ß": "ss", "á": "a", "à": "a", "â": "a", "ã": "a", "å": "a", "ā": "a",
	"é": "e", "è": "e", "ê": "e", "ë": "e", "ē": "e", "í": "i", "ì": "i", "î": "i", "ï": "i", "ī": "i",
	"ó": "o", "ò": "o", "ô": "o", "õ": "o", "ø": "o", "ō": "o", "ú": "u", "ù": "u", "û": "u", "ū": "u",
	"ñ": "n", "ç": "c", "ý": "y", "ÿ": "y", "æ": "ae", "œ": "oe",
}
const UMLAUT_LONG := { "ä": "ae", "ö": "oe", "ü": "ue" }
const ROMAN := { "ii": "2", "iii": "3", "iv": "4", "v": "5", "vi": "6", "vii": "7", "viii": "8", "ix": "9" }


static var _rx_ascii := RegEx.create_from_string("[^a-z0-9]+")


## Kleinschreibung, Zeichen angeglichen, Satzzeichen zu Leerzeichen, römische Zahlen als Ziffern.
static func norm(s: String, long_umlauts := false) -> String:
	var low := s.to_lower()
	var out := ""
	if low.to_utf8_buffer().size() == low.length():
		# Nur ASCII (fast alle Namen): ohne Schleife über jedes Zeichen – die Bibliothek wird beim
		# Öffnen der Suche einmal ganz angeglichen.
		out = _rx_ascii.sub(low, " ", true)
	else:
		for ch in low:
			if long_umlauts and UMLAUT_LONG.has(ch):
				out += UMLAUT_LONG[ch]
			elif FOLD.has(ch):
				out += FOLD[ch]
			elif (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
				out += ch
			elif ch.to_upper() != ch.to_lower():
				out += ch               # andere Schriften (Japanisch, Kyrillisch …) bleiben
			else:
				out += " "
	var words := PackedStringArray()
	for w in out.split(" ", false):
		words.append(str(ROMAN.get(w, w)))
	return " ".join(words)


## Beide Schreibweisen eines Namens (Umlaut ohne Punkte und als „ue“); meist ist es nur eine.
static func variants(s: String) -> PackedStringArray:
	var a := norm(s)
	var b := norm(s, true)
	return PackedStringArray([a]) if a == b else PackedStringArray([a, b])


## Wie gut passt q zu text? 0 = gar nicht. Je höher, desto weiter vorn.
static func score(q: String, text: String) -> int:
	var qn := norm(q)
	if qn == "":
		return 0
	var best := 0
	var memo := {}
	for tn in variants(text):
		best = maxi(best, _score_norm(qn, tn, memo))
	return best


## memo: Tippfehler je Paar Suchwort/Wort, gilt für eine Eingabe (dieselben Wörter kommen in
## vielen Namen vor: „the“, „of“, „edition“ …).
static func _score_norm(qn: String, tn: String, memo: Dictionary) -> int:
	if tn == "":
		return 0
	if tn == qn:
		return EXACT
	# Kürzere Namen zuerst, wenn sie gleich gut passen („Hades“ vor „Hades II“).
	var shorter := clampi(40 - tn.length(), 0, 40)
	if tn.begins_with(qn):
		return PREFIX + shorter
	var words := tn.split(" ", false)
	var qwords := qn.split(" ", false)
	if qwords.size() == 1:
		for w in words:
			if w.begins_with(qn):
				return WORD_PREFIX + shorter
	elif _all_prefixes(qwords, words):
		return ALL_WORDS + shorter
	if qwords.size() == 1 and qn.length() >= 2 and _initials(words).begins_with(qn):
		return INITIALS + shorter
	if qn.length() >= 3 and tn.contains(qn):
		return INSIDE + shorter
	var typos := _typo_cost(qwords, words, memo)
	if typos >= 0:
		return TYPO - typos * 40 + shorter
	return 0


## Jedes Suchwort ist der Anfang eines anderen Wortes im Namen (Reihenfolge egal).
static func _all_prefixes(qwords: PackedStringArray, words: PackedStringArray) -> bool:
	var used := {}
	for q in qwords:
		var hit := -1
		for i in words.size():
			if not used.has(i) and words[i].begins_with(q):
				hit = i
				break
		if hit < 0:
			return false
		used[hit] = true
	return true


static func _initials(words: PackedStringArray) -> String:
	var s := ""
	for w in words:
		# Zahlen zählen ganz („gta5“ für „Grand Theft Auto V“).
		s += w if w.is_valid_int() else w.left(1)
	return s


## Summe der Tippfehler, wenn jedes Suchwort (bis auf einen Fehler, ab 8 Zeichen zwei) zum Anfang
## eines Wortes im Namen passt; -1 wenn eines gar nicht passt. Kurze Wörter müssen genau stimmen.
static func _typo_cost(qwords: PackedStringArray, words: PackedStringArray, memo: Dictionary) -> int:
	var total := 0
	var any_typo := false
	for q in qwords:
		var best := -1
		var most := 2 if q.length() >= 8 else 1
		for w in words:
			var d: int
			if w.begins_with(q):
				d = 0
			elif q.length() < MIN_TYPO_LEN or w.length() < q.length() - most:
				continue
			else:
				# Schnelle Vorprüfung vor dem Rechnen: Bei höchstens n Fehlern steht eines der ersten
				# n + 1 Zeichen des Suchworts auch unter den ersten 2n + 1 des Wortes.
				var head := w.left(2 * most + 1)
				if not (head.contains(q[0]) or head.contains(q[1]) or (most > 1 and head.contains(q[2]))):
					continue
				var mk := q + "|" + w
				if memo.has(mk):
					d = memo[mk]
				else:
					# Gleich lang wie das Suchwort vergleichen: „zeld“ soll zu „zelda“ passen.
					d = mini(distance(q, w.left(q.length()), most), distance(q, w, most))
					memo[mk] = d
				if d > most:
					continue
			if best < 0 or d < best:
				best = d
		if best < 0:
			return -1
		total += best
		any_typo = any_typo or best > 0
	return total if any_typo else -1


## Damerau-Levenshtein (Vertauschen zweier Nachbarn zählt als ein Fehler). cap: mehr als so viele
## Fehler interessieren nicht – dann früh aufhören (Ergebnis ist dann nur „mehr als cap“).
static func distance(a: String, b: String, cap := -1) -> int:
	var n := a.length()
	var m := b.length()
	if n == 0:
		return m
	if m == 0:
		return n
	var prev2 := PackedInt32Array()
	var prev := PackedInt32Array()
	prev.resize(m + 1)
	for j in m + 1:
		prev[j] = j
	for i in range(1, n + 1):
		var cur := PackedInt32Array()
		cur.resize(m + 1)
		cur[0] = i
		for j in range(1, m + 1):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			var v := mini(mini(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost)
			if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
				v = mini(v, prev2[j - 2] + 1)
			cur[j] = v
		if cap >= 0 and Array(cur).min() > cap:
			return cap + 1
		prev2 = prev
		prev = cur
	return prev[m]


## Die besten Einträge zu q: text_of(item) → Name, weight_of(item) → Rang bei gleich guter Art von
## Treffer (z. B. zuletzt gespielt) – erst danach entscheidet der kürzere Name. Sonst bleibt die
## Reihenfolge, wie sie kam. limit 0 = alle.
static func best(items: Array, q: String, text_of: Callable, weight_of: Callable, limit: int) -> Array:
	return rank(prepare(items, text_of, weight_of), q, limit)


## Für lange Listen beim Tippen: die Namen einmal angleichen, danach je Eingabe nur vergleichen.
static func prepare(items: Array, text_of: Callable, weight_of := Callable()) -> Array:
	var out: Array = []
	for it in items:
		out.append([variants(str(text_of.call(it))), float(weight_of.call(it)) if weight_of.is_valid() else 0.0, out.size(), it])
	return out


static func rank(prepared: Array, q: String, limit: int) -> Array:
	var qn := norm(q)
	if qn == "":
		return []
	var memo := {}
	var scored: Array = []
	for p in prepared:
		var s := 0
		for tn in p[0]:
			s = maxi(s, _score_norm(qn, tn, memo))
		if s > 0:
			scored.append([s, p[1], p[2], p[3]])
	scored.sort_custom(func(x: Array, y: Array) -> bool:
		var cx := floori(float(x[0]) / 100.0)
		var cy := floori(float(y[0]) / 100.0)
		if cx != cy:
			return cx > cy
		if x[1] != y[1]:
			return x[1] > y[1]
		if x[0] != y[0]:
			return x[0] > y[0]
		return x[2] < y[2]
	)
	if limit > 0:
		scored = scored.slice(0, limit)
	return scored.map(func(x: Array) -> Variant: return x[3])

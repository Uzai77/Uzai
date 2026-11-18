extends RefCounted
## Namen finden, unter denen freie Bilder eines Emulator-Spiels liegen.
## Libretro benennt Bilder wie die Spieldatenbanken ("Shadow of the Colossus (Europe)"), ROM-Dateien
## heißen oft anders ("Shadow of the Colossus.iso", "shadow_of_the_colossus [PAL]"). Hier wird
## unscharf verglichen. Dazu die Auswahl passender Wikipedia-Seiten und Spielszenen.
## Alles ohne Netz, damit es sich testen lässt; geladen wird in Media.

const Fremd := preload("res://src/core/fremd.gd")

## Bevorzugte Regionen (deutsche Fassung zuerst), alles andere dahinter.
const REGIONS := ["germany", "europe", "world", "usa", "japan"]
## Fassungen, die man lieber nicht zeigt.
const AVOID := ["beta", "proto", "demo", "kiosk", "sample", "promo", "debug", "hack", "unl", "pirate"]


## Vergleichbare Form: klein, ohne Klammern, "&" als "and", ", The" vorne, nur Buchstaben/Ziffern.
const SEQUEL := ["ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "2", "3", "4", "5"]
## Akzente vergleichbar machen („Pokémon“ = „Pokemon“, „Ōkami“ = „Okami“).
const ACCENTS := { "é": "e", "è": "e", "ê": "e", "ë": "e", "á": "a", "à": "a", "â": "a", "ä": "a", "ā": "a",
	"ó": "o", "ò": "o", "ô": "o", "ö": "o", "ō": "o", "ú": "u", "ù": "u", "û": "u", "ü": "u", "ū": "u",
	"í": "i", "ì": "i", "î": "i", "ï": "i", "ñ": "n", "ç": "c", "ß": "ss" }
## Beim Laden übersetzt und danach nur gelesen: build_norms läuft im Hilfsfaden (Media).
static var _re_br := RegEx.create_from_string("[\\(\\[][^\\)\\]]*[\\)\\]]")
static var _re_ws := RegEx.create_from_string("[^a-z0-9]+")


static func norm(s: String) -> String:
	var t := _re_br.sub(s.to_lower(), " ", true)
	# Akzente nur, wenn der Name überhaupt etwas außerhalb von ASCII enthält (die allermeisten nicht): 25 Durchgänge
	# durch den Text weniger je Name.
	if t.to_utf8_buffer().size() != t.length():
		for k in ACCENTS:
			t = t.replace(k, ACCENTS[k])
	# "Legend of Zelda, The - A Link to the Past" → "the legend of zelda - a link to the past"
	var comma := t.find(", the")
	if comma > 0:
		t = "the " + t.substr(0, comma) + t.substr(comma + 5)
	# "&" heißt bei Libretro "_", in Dateinamen oft "and": beides fällt weg.
	t = t.replace("&", " ").replace("_", " ").replace("'", "").replace("’", "")
	t = " " + _re_ws.sub(t, " ", true) + " "
	return t.replace(" and ", " ").strip_edges()


static func tokens(s: String) -> PackedStringArray:
	return norm(s).split(" ", false)


## Region und Zustand aus den Klammern lesen: kleiner ist besser.
static func rank(name: String) -> int:
	var low := name.to_lower()
	var score := 50
	for i in REGIONS.size():
		if low.contains("(" + REGIONS[i]) or low.contains(", " + REGIONS[i]):
			score = i * 5
			break
	for a in AVOID:
		if low.contains("(" + a) or low.contains(" " + a + ")"):
			score += 100
	if low.contains("(rev") or low.contains("(v1") or low.contains("(v2"):
		score += 1
	if low.contains("(disc") and not low.contains("(disc 1"):
		score += 20
	return score


## Wie gut zwei Titel zusammenpassen (0 … 1). Gleich nach norm() = 1.
static func similarity(a: String, b: String) -> float:
	var na := norm(a)
	var nb := norm(b)
	if na == "" or nb == "":
		return 0.0
	return _sim_norm(na, na.split(" ", false), nb)


## Verzeichnis vorbereiten: vergleichbare Form -> alle Bildnamen dazu.
static func build_norms(names: PackedStringArray) -> Dictionary:
	var out := {}
	for n in names:
		var k := norm(n)
		if k == "":
			continue
		if not out.has(k):
			out[k] = PackedStringArray()
		out[k].append(n)
	return out


## Bester Bildname aus einem Verzeichnis für die Namen eines Spiels ("" wenn nichts passt).
## norms: vorbereitetes Verzeichnis (build_norms), spart bei großen Systemen viel Zeit.
static func best_name(wanted: PackedStringArray, names: PackedStringArray, norms: Dictionary = {}, min_sim := 0.75) -> String:
	# Erst exakt (Datei heißt schon wie bei Libretro).
	for w in wanted:
		if w in names:
			return w
	if norms.is_empty():
		norms = build_norms(names)
	# Dann gleicher Titel, beste Region/Fassung.
	for w in wanted:
		var nw := norm(w)
		if norms.has(nw):
			return _best_ranked(norms[nw])
	# Dann ähnlich (fehlender Untertitel, andere Schreibweise).
	var best_key := ""
	var best_s := 0.0
	for w in wanted:
		var nw := norm(w)
		if nw == "":
			continue
		var tw := nw.split(" ", false)
		for k in norms.keys():
			# Schneller Vorfilter: das erste Wort muss vorkommen.
			if not (k as String).contains(tw[0]):
				continue
			var sim := _sim_norm(nw, tw, k)
			if sim < min_sim:
				continue
			# Bei gleicher Ähnlichkeit gewinnt die bessere Region/Fassung.
			sim -= rank(_best_ranked(norms[k])) * 0.0005
			if sim > best_s:
				best_s = sim
				best_key = k
	if best_key == "":
		return ""
	return _best_ranked(norms[best_key])


static func _best_ranked(list: PackedStringArray) -> String:
	var best := ""
	var best_r := 1 << 30
	for n in list:
		var r := rank(n)
		if r < best_r:
			best_r = r
			best = n
	return best


static func _sim_norm(na: String, ta: PackedStringArray, nb: String) -> float:
	if na == nb:
		return 1.0
	var tb := nb.split(" ", false)
	var common := 0
	for t in ta:
		if t in tb:
			common += 1
	var j := float(common) / float(maxi(ta.size() + tb.size() - common, 1))
	# Untertitel fehlt auf einer Seite („Okami“ ↔ „Okami HD“) – aber keine Fortsetzung
	# („Kingdom Hearts“ ≠ „Kingdom Hearts II“). Mehr gemeinsame Wörter gewinnen.
	if nb.begins_with(na + " ") or na.begins_with(nb + " "):
		var longer := nb if nb.length() > na.length() else na
		var shorter := na if longer == nb else nb
		var extra := longer.substr(shorter.length() + 1).get_slice(" ", 0)
		if not (extra.is_valid_int() or extra in SEQUEL):
			j = maxf(j, 0.78 + 0.01 * common)
	return j


## Dasselbe aus der rohen Antwort – für den Hilfsfaden (Media): Das Verzeichnis eines großen Systems hat über
## 10.000 Namen; gemessen an 12.000: die Verzeichnisseite (1,5 MB) 35 ms, die GitHub-Baumantwort (3 MB) 151 ms.
static func parse_listing_bytes(body: PackedByteArray) -> PackedStringArray:
	return parse_listing(body.get_string_from_utf8())


## Bildnamen aus einer Verzeichnisseite (nginx/Apache) oder einer GitHub-Baumantwort.
static func parse_listing(body: String) -> PackedStringArray:
	var out := PackedStringArray()
	var data: Variant = Fremd.json(body) if body.begins_with("{") else null
	if data is Dictionary and data.get("tree") is Array:
		for e in Fremd.zeilen(data.tree):
			var p := str(e.get("path", ""))
			if p.to_lower().ends_with(".png"):
				out.append(p.get_file().get_basename())
		return out
	var re := RegEx.new()
	re.compile("href=\"([^\"/?]+\\.png)\"")
	var seen := {}
	for m in re.search_all(body):
		var n := m.get_string(1).uri_decode().get_basename()
		if not seen.has(n):
			seen[n] = true
			out.append(n)
	return out


## Aus Wikipedia-Suchergebnissen die Seite, die wirklich das Spiel ist ("" sonst).
static func wiki_pick(results: Array, title: String) -> String:
	var best := ""
	var best_s := 0.0
	for r in results:
		var t := str(r.get("title", "")) if r is Dictionary else str(r)
		var bare := t
		var paren := t.find(" (")
		if paren > 0:
			bare = t.substr(0, paren)
		var s := similarity(bare, title)
		if t.to_lower().contains("video game") or t.to_lower().contains("videospiel"):
			s += 0.05
		if s > best_s:
			best_s = s
			best = t
	return best if best_s >= 0.7 else ""


const SHOT_WORDS := ["screenshot", "gameplay", "screen", "ingame", "in-game", "scene", "battle", "combat", "level", "stage"]
const SHOT_NOT := ["logo", "cover", "boxart", "box art", "_box", " box", "box_", "box.", "icon", "artwork", "poster", "flag", "console", "controller",
		"wordmark", "symbol", "portal", "commons-", "question_book", "ambox", "edit-clear", "wikiquote", "wiktionary", "photo"]


## Dateinamen einer Wikipedia-Seite, die nach Spielszene aussehen.
static func wiki_shots(files: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for f in files:
		var n := str(f.get("title", "")) if f is Dictionary else str(f)
		var low := n.to_lower()
		if not (low.ends_with(".png") or low.ends_with(".jpg") or low.ends_with(".jpeg")):
			continue
		if SHOT_NOT.any(func(w): return low.contains(w)):
			continue
		if SHOT_WORDS.any(func(w): return low.contains(w)):
			out.append(n)
	return out

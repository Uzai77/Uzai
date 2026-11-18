extends Translation
## Übersetzungen (Punkte 8, 54). Uzai ist auf Deutsch geschrieben; andere Sprachen stehen in
## i18n/<sprache>.json als „deutscher Text → Übersetzung“. Godot übersetzt jeden Text in Labels,
## Knöpfen und Hinweisen von selbst über diese Klasse; gezeichnete Texte gehen über tr().
##
## Stufen, damit auch zusammengesetzte Texte passen, ohne jede Stelle im Code anzufassen:
## 1. genau („Einstellungen“ → „Settings“),
## 2. Muster mit festem Anfang („Läuft: %s“, „noch %d Min.“) – die eingesetzten Teile werden
##    selbst noch einmal übersetzt (Bereichsnamen, „vor 3 Std.“), Namen und Titel bleiben,
## 3. Zeilen mit „ · “ Stück für Stück („Weiterschauen · noch 18 Min.“),
## 4. Bruchstücke, die im Code mit + angehängt werden: vorn („Zuletzt online “ + Zeit) und
##    hinten (Name + „ ist live in deinem Sprachkanal.“), nur am Rand des Textes,
## 5. Muster, die mit einem Platzhalter beginnen („%d neue Videos“). Solche mit nur einem kurzen
##    Wort zwischen zwei Platzhaltern („%s von %s“) nur, wenn ein Teil eine Zahl ist – sonst
##    griffen sie in Videotitel und Namen in anderer Sprache,
## 6. lange Bruchstücke mitten im Text; kurze („ und “, „an “) nie – sie landeten sonst mitten in
##    Spielnamen und fremdsprachigen Titeln,
## 7. zuletzt reine Gliederungsmuster ohne Wörter („%s: %s“, „„%s““) mit übersetzten Teilen.
## Ergebnisse werden gemerkt (Texte wiederholen sich ständig).
##
## Mehrzahl: Deutsch hat oft eine Form für beides („3 Titel“), Englisch nicht. count() fragt
## deshalb mit Kontext „1“ oder „n“; der Katalog hat dafür Einträge wie „Titel#n“ → „tracks“.

const Fremd := preload("res://src/core/fremd.gd")

const DIR := "res://i18n"
const LANGS := [["de", "Deutsch"], ["en", "English"]]
const CACHE_MAX := 6000
## Wie fremde Dienste die eingestellte Sprache nennen. Inhalte (Shop-Texte, Erfolge, Filmangaben,
## Spotify-Mixe) kommen so in derselben Sprache wie die Oberfläche. Das Land für Preise und Angebote
## ist eine eigene Frage: land_fuer().
## names: so heißt die Sprache in Steams Sprachliste.
const API := {
	"de": { "steam": "german", "tmdb": "de-DE", "spotify": "de_DE", "epic": "de", "accept": "de,en;q=0.8", "names": ["deutsch", "german"] },
	"en": { "steam": "english", "tmdb": "en-US", "spotify": "en_US", "epic": "en-US", "accept": "en,de;q=0.5", "names": ["english", "englisch"] },
}
## Länder, die die Einstellung „Land“ anbietet (Einstellungen › System): [Kennung, Name]. Jede andere
## Kennung aus zwei Buchstaben gilt ebenfalls (von Hand in der Einstellungsdatei).
const LAENDER := [["DE", "Deutschland"], ["AT", "Österreich"], ["CH", "Schweiz"], ["US", "USA"], ["GB", "Großbritannien"],
	["CA", "Kanada"], ["AU", "Australien"], ["FR", "Frankreich"], ["ES", "Spanien"], ["IT", "Italien"], ["NL", "Niederlande"],
	["PL", "Polen"]]
## Währung je Land (wo sie nicht Euro ist) und ihr Zeichen; unbekannte Währungen stehen mit ihrem Kürzel da.
const WAEHRUNG := { "US": "USD", "GB": "GBP", "CH": "CHF", "CA": "CAD", "AU": "AUD", "PL": "PLN" }
const WAEHRUNG_ZEICHEN := { "EUR": "€", "USD": "$", "GBP": "£", "CAD": "CA$", "AUD": "A$", "PLN": "zł" }
## Zeitzone je Land für Dienste, die eine nennen wollen (Hauptstadt bzw. größte Zone).
const ZEITZONE := { "DE": "Europe/Berlin", "AT": "Europe/Vienna", "CH": "Europe/Zurich", "US": "America/New_York", "GB": "Europe/London",
	"CA": "America/Toronto", "AU": "Australia/Sydney", "FR": "Europe/Paris", "ES": "Europe/Madrid", "IT": "Europe/Rome",
	"NL": "Europe/Amsterdam", "PL": "Europe/Warsaw" }
const INFIX_MIN := 10             ## Bruchstücke mitten im Text: so viele Zeichen mindestens
const WEAK_WORDS := 6             ## Muster %s … %s mit weniger Buchstaben brauchen eine Zahl
const DEPTH_MAX := 3
const MONTHS := ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
const MONTHS_SHORT := ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."]

var _exact := {}
var _buckets := {}                ## erste zwei Zeichen → [[RegEx, Übersetzung, schwach], …]
var _tails := {}                  ## letzte zwei Zeichen (Muster, die mit einem Platzhalter beginnen)
var _loose: Array = []            ## Muster ohne festen Anfang und ohne festes Ende
var _structural: Array = []       ## Muster ohne Wörter („%s: %s“): erst, wenn sonst nichts passt
var _prefixes: Array = []         ## [deutsch, übersetzt], längste zuerst: „Läuft: “
var _suffixes: Array = []         ## „ ist live in deinem Sprachkanal.“
var _infixes: Array = []          ## „ und dann weiter mit “ (lang)
var _sep := RegEx.create_from_string("\\s*·\\s+")   ## Trenner in Zeilen wie „A  ·  B“
var _lines := RegEx.create_from_string("\\n+")      ## Zeilen und Absätze eines längeren Textes
var _cache := {}
var _n_patterns := 0

static var _active: Translation


## Sprache einstellen (beim Start, vor dem Aufbau der Oberfläche). Deutsch braucht nichts.
static func apply(code: String) -> void:
	TranslationServer.set_locale(code if code != "" else "de")
	if code == "de" or code == "":
		return
	var t = load("res://src/core/lang.gd").new()
	if t.load_catalog(DIR.path_join(code + ".json")):
		t.locale = code
		TranslationServer.add_translation(t)
		_active = t


## Beim Beenden abmelden: Godot stürzt sonst beim Aufräumen über die Skript-Übersetzung.
static func release() -> void:
	if _active != null:
		TranslationServer.remove_translation(_active)
		_active = null


func load_catalog(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var d: Variant = Fremd.json_roh(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		return false
	load_dict(d)
	return true


func load_dict(d: Dictionary) -> void:
	for k in d:
		var src := str(k)
		var dst := str(d[k])
		if src == "" or dst == "":
			continue
		if _has_slot(src):
			_add_pattern(src, dst)
			# Auch die Vorlage selbst: TranslationServer.translate("%s und %s") % [a, b]
			if not dst.contains("{0}"):
				_exact[src] = dst
			continue
		_exact[src] = dst
		var s := src.strip_edges()
		if s == src or s.length() < 2:
			continue
		var lead := src.length() - src.strip_edges(true, false).length() > 0
		var trail := src.length() - src.strip_edges(false, true).length() > 0
		if lead and trail:
			if s.length() >= INFIX_MIN:
				_infixes.append([src, dst])
		elif trail:
			_prefixes.append([src, dst])
		else:
			_suffixes.append([src, dst])
	for list in [_prefixes, _suffixes, _infixes]:
		list.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]).length() > str(b[0]).length())
	# Muster: das mit dem meisten festen Text zuerst („am Stück gespielt – … %s …“ vor „am %s“).
	var lists: Array = [_structural, _loose]
	lists.append_array(_buckets.values())
	lists.append_array(_tails.values())
	for list in lists:
		list.sort_custom(func(a: Array, b: Array) -> bool: return int(a[3]) > int(b[3]))


## „3 Spiele“: Zahl und Wort in der eingestellten Sprache (Einzahl/Mehrzahl über den Kontext).
static func count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, TranslationServer.translate(one if n == 1 else many, "1" if n == 1 else "n")]


## Name der eingestellten Sprache in ihr selbst („Deutsch“, „English“).
static func own_name() -> String:
	for l in LANGS:
		if l[0] == TranslationServer.get_locale().left(2):
			return l[1]
	return LANGS[0][1]


## Land für Preise und Angebote (Steam, Epic) als zwei Großbuchstaben. wahl: die Einstellung
## („auto“ oder eine Kennung), sprache: Sprache der Oberfläche („de“, „en_US“), system: was Windows
## nennt (OS.get_locale(), etwa „de_AT“ oder „en-GB“). Eine eigene Wahl geht vor. Sonst entscheidet
## die Sprache: Deutsch heißt Deutschland – außer Windows nennt Österreich oder die Schweiz; jede
## andere Sprache nimmt das Land, das Windows nennt, und ohne Angabe die USA. Config.land() ruft das.
static func land_fuer(wahl: String, sprache: String, system: String) -> String:
	var eigen := wahl.strip_edges().to_upper()
	if _ist_land(eigen):
		return eigen
	var sys := land_aus(system)
	if sprache.left(2) == "de":
		return sys if sys in ["AT", "CH"] else "DE"
	return sys if sys != "" else "US"


## Das Land in einer Sprachkennung: „de_AT“, „en-GB“, „zh_Hans_CN“, „de_DE.UTF-8“ → „AT“, „GB“,
## „CN“, „DE“. Ohne Land "".
static func land_aus(kennung: String) -> String:
	var teile := kennung.get_slice(".", 0).get_slice("@", 0).replace("-", "_").split("_")
	for i in range(1, teile.size()):
		if _ist_land(teile[i].to_upper()) and teile[i] == teile[i].to_upper():
			return teile[i]
	# Manche Systeme schreiben das Land klein („en_gb“): dann zählt der letzte Teil mit zwei Buchstaben.
	if teile.size() >= 2 and _ist_land(teile[teile.size() - 1].to_upper()):
		return teile[teile.size() - 1].to_upper()
	return ""


static func _ist_land(s: String) -> bool:
	return s.length() == 2 and s[0] >= "A" and s[0] <= "Z" and s[1] >= "A" and s[1] <= "Z"


## Währung, in der ein Land seine Preise nennt (ohne eigene: Euro).
static func waehrung_fuer(land: String) -> String:
	return str(WAEHRUNG.get(land.to_upper(), "EUR"))


## Ein Betrag in Hundertsteln als Text in der Sprache der Oberfläche: Deutsch „12,49 €“ und
## „12,49 $“, Englisch „€12.49“ und „$12.49“; Währungen ohne Zeichen mit Kürzel („CHF 12.49“).
static func betrag(hundertstel: int, waehrung: String) -> String:
	var ganz := int(hundertstel / 100.0)
	var rest := hundertstel % 100
	var zeichen := str(WAEHRUNG_ZEICHEN.get(waehrung, ""))
	if TranslationServer.get_locale().left(2) == "de":
		return "%d,%02d %s" % [ganz, rest, zeichen if zeichen != "" else waehrung]
	return ("%s%d.%02d" % [zeichen, ganz, rest]) if zeichen != "" else ("%s %d.%02d" % [waehrung, ganz, rest])


## Kennung der eingestellten Sprache für einen Dienst (API), z. B. api("steam") → „german“.
static func api(kind: String) -> Variant:
	var d: Dictionary = API.get(TranslationServer.get_locale().left(2), API.de)
	return d[kind]


## Datum in der eingestellten Sprache. Die Reihenfolge steht im Katalog („@tag_monat“ → „{1} {0}“),
## ohne Eintrag gilt die deutsche. {0} Tag, {1} Monatsname, {2} Jahr, {3}/{4} Tag/Monat zweistellig.
## year 0 = ohne Jahr; numeric = „22.10.2026“ (in anderen Sprachen mit kurzem Monatsnamen, eindeutig).
static func date_text(day: int, month: int, year := 0, short := false, numeric := false) -> String:
	var m := clampi(month - 1, 0, 11)
	var name := TranslationServer.translate(MONTHS_SHORT[m] if short or numeric else MONTHS[m])
	var key := "@datum" if numeric else ("@tag_monat_jahr" if year > 0 else "@tag_monat")
	var fmt := TranslationServer.translate(key)
	if fmt == key:
		fmt = "{3}.{4}.{2}" if numeric else ("{0}. {1} {2}" if year > 0 else "{0}. {1}")
	return fmt.replace("{0}", str(day)).replace("{1}", name).replace("{2}", str(year)) \
		.replace("{3}", "%02d" % day).replace("{4}", "%02d" % month)


## Kommazahl in der eingestellten Sprache: „3.5 GB“ wird im Deutschen „3,5 GB“; andere Sprachen
## nennen ihr Zeichen im Katalog („@komma“).
static func dec(text: String) -> String:
	var sep := TranslationServer.translate("@komma")
	return text.replace(".", "," if sep == "@komma" else sep)


## Ganze Zahl mit Tausendertrennung in der eingestellten Sprache: „41.237“, im Englischen „41,237“ (das Gegenstück
## zum Komma aus dec). Die eine Stelle dafür: Vorher gab es sieben Kopien, alle fest mit Punkt – im Englischen las
## sich „6.873 points“ wie eine Kommazahl.
static func tausender(n: int) -> String:
	var s := str(absi(n))
	if s.length() <= 3:
		return str(n)
	var zeichen := "," if TranslationServer.translate("@komma") == &"." else "."
	var out := ""
	while s.length() > 3:
		out = zeichen + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## „März 2019“
static func month_year(month: int, year: int) -> String:
	var name := TranslationServer.translate(MONTHS[clampi(month - 1, 0, 11)])
	var fmt := TranslationServer.translate("@monat_jahr")
	return (fmt if fmt != "@monat_jahr" else "{1} {2}").replace("{1}", name).replace("{2}", str(year))


func _get_message(src_message: StringName, context: StringName) -> StringName:
	var s := String(src_message)
	if s == "" or s.length() > 2000:
		return src_message
	if context != &"" and _exact.has(s + "#" + String(context)):
		return StringName(_exact[s + "#" + String(context)])
	if _cache.has(s):
		return _cache[s]
	var out := translate(s)
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	_cache[s] = StringName(out)
	return _cache[s]


func translate(s: String, depth := 0) -> String:
	if _exact.has(s):
		return _exact[s]
	if depth > DEPTH_MAX:
		return s
	# Lange Texte nur noch Zeile für Zeile (Muster über 600 Zeichen kosten zu viel).
	var long := s.length() > 600
	var p: Variant = null if long else _match(s, depth, [_buckets.get(s.left(2), [])], false)
	if p != null:
		return p
	# Mehrzeilig (Dialoge aus mehreren Absätzen): Zeile für Zeile, dann wie sonst.
	var bits := _split(s, _lines)
	if long and bits.size() == 1:
		return s
	if bits.size() == 1:
		bits = _split(s, _sep)
	if bits.size() > 1:
		var out := ""
		for i in bits.size():
			out += translate(bits[i], depth + 1) if i % 2 == 0 else bits[i]
		return out
	var f := _affix(s, depth)
	if f != s:
		return f
	p = _match(s, depth, [_tails.get(s.right(2), []), _loose], false)
	if p != null:
		return p
	for frag in _infixes:
		if f.contains(str(frag[0])):
			f = f.replace(str(frag[0]), str(frag[1]))
	if f != s:
		return f
	p = _match(s, depth, [_structural], true)
	return p if p != null else s


## Eingesetzter Teil eines Musters: genau oder selbst ein Muster („zuletzt %s“ ← „vor 3 Std.“),
## aber keine Bruchstücke – Namen und Titel bleiben, wie sie sind.
func _part(g: String, depth: int) -> String:
	if _exact.has(g):
		return _exact[g]
	var p: Variant = _match(g, depth, [_buckets.get(g.left(2), []), _tails.get(g.right(2), []), _loose], false) if depth <= DEPTH_MAX else null
	return p if p != null else g


func _match(s: String, depth: int, lists: Array, full: bool) -> Variant:
	for list in lists:
		for p in list:
			var m: RegExMatch = (p[0] as RegEx).search(s)
			if m != null and (not bool(p[2]) or _has_number(m)) and not _spans_sep(m):
				return _fill(str(p[1]), m, depth, full)
	return null


## Ein Platzhalter hat einen „ · “-Trenner verschluckt („Freigeschaltet am %s“ auf der ganzen
## Zeile): dann lieber Stück für Stück.
func _spans_sep(m: RegExMatch) -> bool:
	for i in range(1, m.get_group_count() + 1):
		if _sep.search(m.get_string(i)) != null:
			return true
	return false


static func _has_number(m: RegExMatch) -> bool:
	for i in range(1, m.get_group_count() + 1):
		for ch in m.get_string(i):
			if ch >= "0" and ch <= "9":
				return true
	return false


## „A  ·  B  ·  C“ → [A, Trenner, B, Trenner, C]
func _split(s: String, rx: RegEx) -> PackedStringArray:
	var out := PackedStringArray()
	var at := 0
	for m in rx.search_all(s):
		out.append(s.substr(at, m.get_start() - at))
		out.append(m.get_string())
		at = m.get_end()
	out.append(s.substr(at))
	return out


## Platzhalter im Ziel der Reihe nach füllen; {0}, {1} … erlauben eine andere Reihenfolge.
## full: Teile ganz übersetzen (Gliederungsmuster ohne eigene Wörter).
func _fill(dst: String, m: RegExMatch, depth := 0, full := false) -> String:
	var parts: Array = []
	for i in range(1, m.get_group_count() + 1):
		parts.append(translate(m.get_string(i), depth + 1) if full else _part(m.get_string(i), depth + 1))
	if dst.contains("{0}"):
		var out := dst
		for i in parts.size():
			out = out.replace("{%d}" % i, str(parts[i]))
		return out
	var res := ""
	var i := 0
	var k := 0
	while i < dst.length():
		var ch := dst[i]
		if ch == "%" and i + 1 < dst.length():
			var j := _slot_end(dst, i)
			if j > i:
				res += str(parts[k]) if k < parts.size() else ""
				k += 1
				i = j
				continue
			if dst[i + 1] == "%":
				res += "%"
				i += 2
				continue
		res += ch
		i += 1
	return res


## Vorn und hinten angehängte Bruchstücke; der Rest dazwischen ist meist ein Name oder eine
## Zeit (genau oder als Muster übersetzt).
func _affix(s: String, depth: int) -> String:
	var head := ""
	var tail := ""
	var rest := s
	for f in _prefixes:
		if rest.begins_with(str(f[0])) and rest.length() > str(f[0]).length():
			head = f[1]
			rest = rest.substr(str(f[0]).length())
			break
	for f in _suffixes:
		if rest.ends_with(str(f[0])) and rest.length() > str(f[0]).length():
			tail = f[1]
			rest = rest.left(rest.length() - str(f[0]).length())
			break
	if head == "" and tail == "":
		return s
	return head + _part(rest, depth + 1) + tail


func _add_pattern(src: String, dst: String) -> void:
	var rx := "^"
	var i := 0
	var lit := ""
	var prefix := ""
	var first_slot := -1
	var slots_len := 0
	while i < src.length():
		var j := _slot_end(src, i) if src[i] == "%" else i
		if j > i:
			if first_slot < 0:
				first_slot = i
				prefix = lit
			rx += _escape(lit)
			lit = ""
			var spec := src.substr(i, j - i)
			slots_len += spec.length()
			# Text ohne Leerzeichen am Rand: sonst schluckte „Zuletzt %s · %s“ einen „  ·  “-Trenner.
			# %d nimmt auch Zahlen mit Tausendertrennern („1.000 Stunden“, „1,000 Stunden“): Sonst griff bei großen
			# Zahlen kein Muster mehr, und es blieb halb deutsch („5,000 Stunden in total“).
			var zahl := "(-?\\d{1,3}(?:[.,]\\d{3})+|-?\\d+)"
			rx += zahl if spec.ends_with("d") else ("(-?[\\d.,]+)" if spec.ends_with("f") else "((?:\\S(?:.*?\\S)?)?)")
			i = j
			continue
		if src[i] == "%" and i + 1 < src.length() and src[i + 1] == "%":
			lit += "%"
			i += 2
			continue
		lit += src[i]
		i += 1
	rx += _escape(lit) + "$"
	var r := RegEx.new()
	if r.compile(rx) != OK:
		return
	var words := _words(src)
	var weak := first_slot == 0 and lit == "" and words.length() < WEAK_WORDS
	# Viertes Feld: wie viel fester Text – genauere Muster kommen zuerst dran (load_dict sortiert);
	# bei Gleichstand bleibt die Reihenfolge des Katalogs (fixed * 100000 - laufende Nummer).
	_n_patterns += 1
	var fixed := (src.length() - slots_len) * 100000 - _n_patterns
	if words == "":
		_structural.append([r, dst, false, fixed])
	elif first_slot != 0 and prefix.length() >= 2:
		_bucket(_buckets, prefix.left(2), [r, dst, false, fixed])
	elif lit.length() >= 2:
		_bucket(_tails, lit.right(2), [r, dst, false, fixed])
	else:
		_loose.append([r, dst, weak, fixed])


static func _bucket(d: Dictionary, key: String, item: Array) -> void:
	if not d.has(key):
		d[key] = []
	d[key].append(item)


## Ende eines Platzhalters ab „%“ (%s, %d, %02d, %.1f, %5.2f …), sonst start.
static func _slot_end(s: String, start: int) -> int:
	var i := start + 1
	while i < s.length() and (s[i] in "0123456789.-"):
		i += 1
	if i < s.length() and s[i] in "sdfxX":
		return i + 1
	return start


## Die Buchstaben eines Musters ohne Platzhalter („%s: %s“ hat keine).
static func _words(s: String) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		var j := _slot_end(s, i) if s[i] == "%" else i
		if j > i:
			i = j
			continue
		if s[i].to_upper() != s[i].to_lower():
			out += s[i]
		i += 1
	return out


static func _has_slot(s: String) -> bool:
	for i in s.length():
		if s[i] == "%" and _slot_end(s, i) > i:
			return true
	return false


static func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if ch in ".^$*+?()[]{}|\\/" else ch
	return out

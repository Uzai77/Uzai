extends RefCounted
## Werbe- und Tracker-Blocker des Uzai-Browsers – Regeln als Daten, reine Logik ohne Oberfläche.
## Die Entscheidung je Anfrage trifft im Betrieb der Kern (helper/uzai-browser-gemeinsam.cs, UzbFilter –
## prozessintern, Mikrosekunden); dies ist die zweite, gleich gebaute Fassung in Uzai: für die Tests mit derselben
## Tabelle (tests/fixtures/browser_filter.json), für den Vorführmodus und um die mitgelieferte Liste zu prüfen.
## Regeln können nur sperren und verstecken – nie Code. Hauptdokumente werden nie gesperrt.
##
## Dateiformat (assets/browser/filter/filter.gz, gebaut von tools/filter_bauen.py aus EasyList, EasyPrivacy und
## EasyList Cookie; Lizenz und Prüfsumme in assets/browser/filter/LIZENZ.txt), eine Regel je Zeile, erstes Zeichen:
##   d <domäne>                   Anfragen an diese Domäne und ihre Unterdomänen sperren
##   t <domäne>                   … nur als dritte Partei (die Seite ist eine andere Domäne)
##   p <muster>|<flags>|<seiten>  Adressmuster: || Anker am Namen, ^ Trenner, * beliebig, | Anfang/Ende; flags: 3 nur
##                                dritte Partei, 1 nur erste, Typbuchstaben s i c x f m o F p O, ~ davor = alle außer;
##                                seiten: nur dort (Komma, ~ nimmt aus)
##   a <muster>|<flags>|<seiten>  Ausnahme: nie sperren
##   h <selektor>                 überall verstecken;  s <seiten>|<selektor> nur dort;  e <seiten>|<selektor> dort nicht

const MAX_ZEILEN := 400000
const MAX_ZEILE := 600
const MAX_BYTES := 16 * 1024 * 1024
const MAX_SELEKTOREN := 24000
## SHA-256 der mitgelieferten Liste (gleich im Helfer, $script:KernFilterSha); geprüft von tests/logic_browser_filter.gd.
const LISTE := "res://assets/browser/filter/filter.gz"
const LISTE_SHA256 := "32275b8fce9d1b36ba8493b3cb160694d438c90ce4275ace4c3d87f2e02329f6"
const TYPEN := { 1: "f", 2: "c", 3: "s", 4: "i", 5: "F", 7: "o", 8: "m", 13: "x", 14: "p" }
const ZWEISTUFIG := ["co.uk", "org.uk", "gov.uk", "ac.uk", "me.uk", "com.au", "net.au", "org.au", "co.nz", "co.jp", "ne.jp", "or.jp", "com.br",
	"com.mx", "com.ar", "co.za", "com.tr", "co.in", "co.kr", "com.cn", "com.tw", "com.hk", "com.sg", "co.il", "com.pl"]

var domaenen := {}
var dritte := {}
var index := {}          ## Token → [Muster]
var rest: Array = []
var aus_index := {}
var aus_rest: Array = []
var verstecken: Array = []
var verstecken_seiten := {}
var verstecken_ausnahmen := {}
var regeln := 0


## Ressourcenart von CEF (cef_resource_type_t) als Typbuchstabe.
static func typ(art: int) -> String:
	return str(TYPEN.get(art, "O"))


## Liste aus einer Datei (gz oder Text) laden; Grenzen wie im Kern.
static func laden(pfad: String) -> RefCounted:
	var f := new()
	var roh := FileAccess.get_file_as_bytes(pfad)
	if roh.is_empty() or roh.size() > MAX_BYTES:
		return f
	if roh.size() > 2 and roh[0] == 0x1f and roh[1] == 0x8b:
		roh = roh.decompress_dynamic(MAX_BYTES, FileAccess.COMPRESSION_GZIP)
	f.text_laden(roh.get_string_from_utf8())
	return f


func text_laden(text: String) -> void:
	for zeile in text.split("\n"):
		if regeln > MAX_ZEILEN:
			break
		if zeile.length() < 3 or zeile.length() > MAX_ZEILE or zeile[1] != " ":
			continue
		if zeile_lesen(zeile[0], zeile.substr(2)):
			regeln += 1


## Eine Regel; false = abgelehnt (gleiche Prüfung wie der Kern).
func zeile_lesen(art: String, r: String) -> bool:
	match art:
		"d":
			if not domaene_ok(r):
				return false
			domaenen[r] = true
			return true
		"t":
			if not domaene_ok(r):
				return false
			dritte[r] = true
			return true
		"p", "a":
			var m := muster_lesen(r)
			if m.is_empty():
				return false
			_eintragen(m, aus_index if art == "a" else index, aus_rest if art == "a" else rest)
			return true
		"h":
			if not selektor_ok(r) or verstecken.size() >= MAX_SELEKTOREN:
				return false
			verstecken.append(r)
			return true
		"s", "e":
			var k := r.find("|")
			if k <= 0 or k == r.length() - 1:
				return false
			var sel := r.substr(k + 1)
			if not selektor_ok(sel):
				return false
			for d in r.substr(0, k).split(","):
				var dd := d.strip_edges()
				if not domaene_ok(dd):
					continue
				if art == "s":
					if not verstecken_seiten.has(dd):
						verstecken_seiten[dd] = []
					if (verstecken_seiten[dd] as Array).size() < 2000:
						(verstecken_seiten[dd] as Array).append(sel)
				else:
					if not verstecken_ausnahmen.has(dd):
						verstecken_ausnahmen[dd] = {}
					verstecken_ausnahmen[dd][sel] = true
			return true
	return false


static func domaene_ok(d: String) -> bool:
	if d.length() < 3 or d.length() > 253 or not d.contains("."):
		return false
	for ch in d:
		if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-" or ch == "." or ch == "_"):
			return false
	return true


## Selektoren sind nur CSS: keine geschweiften Klammern, kein Semikolon, kein Kommentar, keine Adressen.
static func selektor_ok(s: String) -> bool:
	if s.length() < 2 or s.length() > 300:
		return false
	for ch in s:
		var c := ch.unicode_at(0)
		if ch == "{" or ch == "}" or ch == ";" or c < 32 or ch == "\\" or ch == "/":
			return false
	var low := s.to_lower()
	return not low.contains("url(") and not low.contains("expression") and not s.contains(":has(") and not s.contains("-abp-")


static func muster_lesen(r: String) -> Dictionary:
	var teile := r.split("|")
	var seiten := ""
	var flags := ""
	var text := r
	if teile.size() >= 3:
		seiten = teile[teile.size() - 1]
		flags = teile[teile.size() - 2]
		text = r.substr(0, r.length() - seiten.length() - flags.length() - 2)
	elif teile.size() == 2:
		flags = teile[1]
		text = teile[0]
	if text.length() < 2 or text.length() > 300:
		return {}
	var m := { "host_anker": false, "anfang": false, "ende": false, "nur_dritte": false, "nur_erste": false, "typen": "", "typen_neg": false,
		"seiten": [], "seiten_nicht": [] }
	if text.begins_with("||"):
		m.host_anker = true
		text = text.substr(2)
	elif text.begins_with("|"):
		m.anfang = true
		text = text.substr(1)
	if text.ends_with("|"):
		m.ende = true
		text = text.substr(0, text.length() - 1)
	text = text.to_lower()
	for ch in text:
		var c := ch.unicode_at(0)
		if c <= 32 or c > 126:
			return {}
	if text.is_empty() or text.lstrip("*").rstrip("*").length() < 2:
		return {}
	m["text"] = text
	# Das längste Stück ohne * und ^ muss wörtlich in der Adresse stehen – billige Vorprüfung (find), und ohne
	# Stern davor steht damit auch fest, wo das Muster beginnen muss.
	var lit := literal(text)
	m["lit"] = lit
	m["lit_pos"] = text.find(lit) if lit != "" else -1
	var stern := text.find("*")
	m["lit_frei"] = lit != "" and (stern < 0 or stern > int(m.lit_pos))
	for ch in flags:
		if ch == "3":
			m.nur_dritte = true
		elif ch == "1":
			m.nur_erste = true
		elif ch == "~":
			m.typen_neg = true
		elif "sicxfmoFpO".contains(ch):
			m.typen += ch
		else:
			return {}
	if seiten != "":
		for d in seiten.split(","):
			if d.begins_with("~"):
				if domaene_ok(d.substr(1)):
					(m.seiten_nicht as Array).append(d.substr(1))
			elif domaene_ok(d):
				(m.seiten as Array).append(d)
	return m


func _eintragen(m: Dictionary, idx: Dictionary, sonst: Array) -> void:
	var token := bestes_token(str(m.text))
	if token == "":
		if sonst.size() < 5000:
			sonst.append(m)
		return
	if not idx.has(token):
		idx[token] = []
	(idx[token] as Array).append(m)


## Längster Lauf aus a–z0–9 (mindestens 4), der in jeder passenden Adresse vorkommen muss ("" wenn keiner).
static func bestes_token(text: String) -> String:
	var best := ""
	var i := 0
	while i < text.length():
		var j := i
		while j < text.length() and _alnum(text[j]):
			j += 1
		# Nur ein Lauf, der im Muster beidseitig begrenzt ist (nicht am Anfang, nicht am Ende, nicht neben *):
		# sonst könnte die Adresse einen längeren Lauf haben („/adserver“ trifft auch „/adservers/“).
		if j - i >= 4 and j - i > best.length() and i > 0 and j < text.length() and text[i - 1] != "*" and text[j] != "*":
			best = text.substr(i, j - i)
		i = j + 1
	return best


static func _alnum(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")


# --- Entscheidung ---------------------------------------------------------------------------------------

static func host_von(url: String) -> String:
	var k := url.find("://")
	if k < 0:
		return ""
	var a := k + 3
	var e := a
	while e < url.length() and url[e] != "/" and url[e] != "?" and url[e] != "#":
		e += 1
	var aut := url.substr(a, e - a)
	var at := aut.rfind("@")
	if at >= 0:
		aut = aut.substr(at + 1)
	if aut.begins_with("["):
		var z := aut.find("]")
		return aut.substr(0, z + 1).to_lower() if z > 0 else ""
	var p := aut.find(":")
	if p >= 0:
		aut = aut.substr(0, p)
	return aut.to_lower().trim_suffix(".")


## Registrierbare Domäne (grob): letzte zwei Teile, bei bekannten Endungen drei.
static func site(host: String) -> String:
	var t := host.split(".")
	if t.size() <= 2:
		return host
	var zwei := t[t.size() - 2] + "." + t[t.size() - 1]
	return t[t.size() - 3] + "." + zwei if ZWEISTUFIG.has(zwei) else zwei


static func _in_liste(host: String, liste: Dictionary) -> bool:
	var h := host
	while true:
		if liste.has(h):
			return true
		var p := h.find(".")
		if p < 0:
			return false
		h = h.substr(p + 1)
	return false


static func _seite_trifft(seite: String, liste: Array) -> bool:
	for d in liste:
		if seite == d or seite.ends_with("." + str(d)):
			return true
	return false


## Soll diese Anfrage gesperrt werden? art = cef_resource_type_t, seite = Name der Seite (erste Partei).
func gesperrt(url: String, art: int, seite: String) -> bool:
	if art == 0 or art == 19 or url.length() > 8192:
		return false
	var host := host_von(url)
	if host == "":
		return false
	var low := url.to_lower()
	var seite_low := seite.to_lower()
	var ist_dritte := seite_low == "" or site(host) != site(seite_low)
	var t := typ(art)
	if _trifft(low, ist_dritte, t, seite_low, aus_index, aus_rest):
		return false
	if _in_liste(host, domaenen):
		return true
	if ist_dritte and _in_liste(host, dritte):
		return true
	return _trifft(low, ist_dritte, t, seite_low, index, rest)


func _trifft(low: String, ist_dritte: bool, t: String, seite: String, idx: Dictionary, sonst: Array) -> bool:
	for m in sonst:
		if _passt(m, low, ist_dritte, t, seite):
			return true
	var gesehen := {}
	var i := 0
	while i < low.length():
		var j := i
		while j < low.length() and _alnum(low[j]):
			j += 1
		if j - i >= 4:
			var tok := low.substr(i, j - i)
			if not gesehen.has(tok) and idx.has(tok):
				gesehen[tok] = true
				for m in idx[tok]:
					if _passt(m, low, ist_dritte, t, seite):
						return true
		i = j + 1
	return false


static func _passt(m: Dictionary, low: String, ist_dritte: bool, t: String, seite: String) -> bool:
	if bool(m.nur_dritte) and not ist_dritte:
		return false
	if bool(m.nur_erste) and ist_dritte:
		return false
	var typen := str(m.typen)
	if typen != "":
		var drin := typen.contains(t)
		if (drin if bool(m.typen_neg) else not drin):
			return false
	if not (m.seiten as Array).is_empty() and not _seite_trifft(seite, m.seiten):
		return false
	if not (m.seiten_nicht as Array).is_empty() and _seite_trifft(seite, m.seiten_nicht):
		return false
	var text := str(m.text)
	if str(m.lit) != "" and low.find(str(m.lit)) < 0:
		return false
	if bool(m.host_anker):
		var k := low.find("://")
		if k < 0:
			return false
		var a := k + 3
		var host_ende := a
		while host_ende < low.length() and low[host_ende] != "/" and low[host_ende] != "?" and low[host_ende] != "#":
			host_ende += 1
		for p in range(a, host_ende + 1):
			if p != a and low[p - 1] != ".":
				continue
			if p > a and p >= host_ende:
				break
			if glob(text, 0, low, p, bool(m.ende)):
				return true
		return false
	if bool(m.anfang):
		return glob(text, 0, low, 0, bool(m.ende))
	var lit := str(m.lit)
	if lit == "":
		for p in low.length():
			if text[0] != "*" and text[0] != "^" and low[p] != text[0]:
				continue
			if glob(text, 0, low, p, bool(m.ende)):
				return true
		return false
	var s := 0
	while true:
		var k := low.find(lit, s)
		if k < 0:
			return false
		var start := k - int(m.lit_pos)
		if bool(m.lit_frei):
			if start >= 0 and glob(text, 0, low, start, bool(m.ende)):
				return true
		else:
			# Stern vor dem Stück: jeder Anfang bis dorthin kommt infrage (der Stern findet spätere Stellen selbst).
			for p in range(0, maxi(start, 0) + 1):
				if glob(text, 0, low, p, bool(m.ende)):
					return true
			return false
		s = k + 1
	return false


## Das längste Stück eines Musters ohne * und ^ (mindestens 2 Zeichen), "" wenn keins.
static func literal(text: String) -> String:
	var best := ""
	var i := 0
	while i < text.length():
		var j := i
		while j < text.length() and text[j] != "*" and text[j] != "^":
			j += 1
		if j - i >= 2 and j - i > best.length():
			best = text.substr(i, j - i)
		i = j + 1
	return best


static func trenner(ch: String) -> bool:
	return not (_alnum(ch) or ch == "_" or ch == "-" or ch == "." or ch == "%")


## Muster mit * (beliebig) und ^ (Trenner oder Ende) gegen den Text ab Stelle ti; ende: muss am Ende aufhören.
static func glob(muster: String, mi: int, text: String, ti: int, ende: bool) -> bool:
	var stern_m := -1
	var stern_t := -1
	while true:
		if mi == muster.length():
			if not ende or ti == text.length():
				return true
		else:
			var c := muster[mi]
			if c == "*":
				stern_m = mi
				stern_t = ti
				mi += 1
				continue
			if ti < text.length() and (c == text[ti] or (c == "^" and trenner(text[ti]))):
				mi += 1
				ti += 1
				continue
			if c == "^" and ti == text.length():
				mi += 1
				continue
		if stern_m < 0 or stern_t >= text.length():
			return false
		mi = stern_m + 1
		stern_t += 1
		ti = stern_t
	return false


## Selektoren, die auf dieser Seite versteckt werden (allgemeine ohne die Ausnahmen der Seite, dazu die eigenen).
func kosmetik(seite: String) -> Array:
	var s := seite.to_lower()
	var ausnahmen := {}
	for d in verstecken_ausnahmen:
		if s == d or s.ends_with("." + str(d)):
			ausnahmen.merge(verstecken_ausnahmen[d])
	var out: Array = []
	for sel in verstecken:
		if not ausnahmen.has(sel):
			out.append(sel)
	for d in verstecken_seiten:
		if s == d or s.ends_with("." + str(d)):
			for sel in verstecken_seiten[d]:
				if not ausnahmen.has(sel):
					out.append(sel)
	return out.slice(0, MAX_SELEKTOREN)

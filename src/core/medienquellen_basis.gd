extends RefCounted
## Gemeinsame, reine Bausteine der Filme-Quellen (Plex, Jellyfin, Emby, Stremio-Konto – Roadmap 35):
## Antworten streng lesen, Adressen prüfen, Altersfreigaben deuten und der Kinderfilter. Ohne
## Zustand und ohne Netz, damit alles in tests/logic_medienquellen.gd prüfbar ist.
##
## Bedrohung: Ein Server (oder wer sich im Heimnetz als einer ausgibt) kann beliebige Antworten
## schicken. Darum gilt: nur JSON (nie str_to_var, Expression oder Ressourcen), feste Größen,
## jeder Wert mit Typ und Länge geprüft, Texte ohne Steuerzeichen. Adressen für Bilder und Streams
## baut Uzai selbst aus der Server-Adresse und geprüften Pfaden – nie aus fremden Voll-Adressen.

## Größte Antwort, die Uzai überhaupt liest (Bibliotheken kommen seitenweise).
const MAX_JSON := 4 * 1024 * 1024
## Lange Listen (alle Folgen einer Serie, Stremio-Bibliothek) dürfen etwas größer sein.
const MAX_JSON_BIG := 12 * 1024 * 1024
const TEXT_MAX := 300
const DESC_MAX := 4000

## Altersstufen wie bei Spielen (USK); fremde Systeme werden aufgerundet.
const STEPS := [0, 6, 12, 16, 18]
## Feste Freigaben fremder Systeme (MPAA, US-TV, UK, AU) – vorsichtig auf USK-Stufen gelegt.
const RATINGS := {
	"G": 0, "PG": 6, "PG-13": 12, "R": 16, "NC-17": 18, "X": 18,
	"TV-Y": 0, "TV-Y7": 6, "TV-Y7-FV": 6, "TV-G": 0, "TV-PG": 6, "TV-14": 16, "TV-MA": 18,
	"U": 0, "UC": 0, "12A": 12, "R18": 18, "M": 16, "MA15+": 16, "R18+": 18, "X18+": 18,
	"ALL": 0, "ALLE": 0, "AL": 0, "0+": 0, "BPJM": 18,
}
## Ohne Angabe: „nicht bewertet“ ist keine Freigabe.
const UNRATED := ["NR", "NOT RATED", "UNRATED", "APPROVED", "PASSED", "UR", "NONE", ""]
## Bibliotheken und Genres, die als „für Kinder und Familie“ gelten.
const FAMILY_WORDS := ["kinder", "kids", "kid", "familie", "family", "children", "kinderfilme", "kinderserien"]


# --- Lesen -------------------------------------------------------------------------------------

## JSON aus einer Antwort; null bei zu groß, leer oder kaputt.
static func json(body: PackedByteArray, max_bytes := MAX_JSON) -> Variant:
	if body.is_empty() or body.size() > max_bytes:
		return null
	var js := JSON.new()
	if js.parse(body.get_string_from_utf8()) != OK:
		return null
	return js.data


## Text aus einem fremden Wert: nur Text oder Zahl, ohne Steuerzeichen, höchstens max_len Zeichen.
static func text(v: Variant, max_len := TEXT_MAX) -> String:
	var s := ""
	if v is String:
		s = v
	elif v is int:
		s = str(v)
	elif v is float:
		s = str(int(v)) if float(v) == floorf(float(v)) else str(v)
	else:
		return ""
	if s.length() > max_len * 4:
		s = s.left(max_len * 4)
	var out := ""
	for ch in s:
		var c := ch.unicode_at(0)
		if c == 0x0A and max_len >= DESC_MAX:
			out += "\n"
		elif c < 0x20 or c == 0x7F or (c >= 0x80 and c < 0xA0) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069) or c == 0xFFFD:
			out += " " if c == 0x09 or c == 0x0A or c == 0x0D else ""
		else:
			out += ch
	return out.strip_edges().left(max_len)


## Ganze Zahl aus einem fremden Wert (Zahl oder Ziffern-Text), sonst fallback.
static func num(v: Variant, fallback := 0) -> int:
	if v is int:
		return v
	if v is float and is_finite(float(v)) and absf(float(v)) < 9.0e15:
		return int(v)
	if v is String and (v as String).length() <= 18 and (v as String).is_valid_int():
		return int(v)
	return fallback


static func flag(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return num(v) != 0
	return v is String and (v as String).to_lower() in ["1", "true"]


## Liste aus einem fremden Wert (sonst leer), höchstens max Einträge.
static func arr(v: Variant, max := 2000) -> Array:
	return (v as Array).slice(0, max) if v is Array else []


static func dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


## Kennung nur aus erlaubten Zeichen und mit fester Länge – sonst "".
static func ident(v: Variant, allowed := "hex", min_len := 1, max_len := 64) -> String:
	var s := text(v, max_len + 1)
	if s.length() < min_len or s.length() > max_len:
		return ""
	for ch in s:
		var ok := false
		match allowed:
			"digits": ok = ch >= "0" and ch <= "9"
			"hex": ok = (ch >= "0" and ch <= "9") or (ch >= "a" and ch <= "f") or (ch >= "A" and ch <= "F") or ch == "-"
			"alnum": ok = (ch >= "0" and ch <= "9") or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z")
			"token": ok = (ch >= "0" and ch <= "9") or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch in ["-", "_", "."]
		if not ok:
			return ""
	return s


## Zeitpunkt aus „2026-10-01T18:30:00.000Z“ (oder Sekunden) als Unix-Zeit, 0 wenn unlesbar.
static func iso_time(v: Variant) -> int:
	if v is int or v is float:
		var n := num(v)
		return n if n > 0 and n < 4102444800 else 0
	var s := text(v, 40)
	if s.length() < 19 or s.substr(4, 1) != "-":
		return 0
	var t := Time.get_unix_time_from_datetime_string(s.substr(0, 19))
	return t if t > 0 and t < 4102444800 else 0


static func random_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


# --- Adressen ----------------------------------------------------------------------------------

## Server-Adresse zerlegen: { scheme, host, port, origin, base } oder {} wenn ungültig.
## base = origin plus geprüfter Unterpfad (Server hinter einem Proxy unter /jellyfin).
## Ohne Schema gilt http:// nur für Adressen im Heimnetz, sonst https://.
static func parse_server(url: String, default_port := 0) -> Dictionary:
	var u := url.strip_edges()
	if u == "" or u.length() > 300:
		return {}
	var scheme := ""
	var se := u.find("://")
	if se > 0:
		scheme = u.substr(0, se).to_lower()
		u = u.substr(se + 3)
	if scheme != "" and scheme not in ["http", "https"]:
		return {}
	var path := ""
	var slash := u.find("/")
	if slash >= 0:
		path = u.substr(slash)
		u = u.substr(0, slash)
	if u.contains("@") or u.contains("?") or u.contains("#") or u.contains("\\") or u == "":
		return {}
	var host := u
	var port := 0
	if u.begins_with("["):
		var close := u.find("]")
		if close < 0:
			return {}
		host = u.substr(1, close - 1)
		var rest := u.substr(close + 1)
		if rest.begins_with(":"):
			port = num(rest.substr(1), -1)
		elif rest != "":
			return {}
		if not host.is_valid_ip_address() or not host.contains(":"):
			return {}
	elif u.count(":") == 1:
		host = u.get_slice(":", 0)
		port = num(u.get_slice(":", 1), -1)
	elif u.count(":") > 1:
		return {}
	if port < 0 or port > 65535:
		return {}
	host = host.to_lower()
	if not _host_ok(host):
		return {}
	if scheme == "":
		scheme = "http" if is_private_ip(host) else "https"
	if port == 0:
		port = default_port if default_port > 0 else (443 if scheme == "https" else 80)
	path = path.rstrip("/")
	if path != "" and not _sub_path_ok(path):
		return {}
	var hp := "[%s]" % host if host.contains(":") else host
	var origin := "%s://%s" % [scheme, hp]
	if not ((scheme == "https" and port == 443) or (scheme == "http" and port == 80)):
		origin += ":%d" % port
	return { "scheme": scheme, "host": host, "port": port, "origin": origin, "base": origin + path }


static func _host_ok(host: String) -> bool:
	if host.is_valid_ip_address():
		return true
	if host.length() > 253 or host.begins_with(".") or host.ends_with(".") or host.contains(".."):
		return false
	for ch in host:
		if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch in [".", "-"]):
			return false
	return true


static func _sub_path_ok(p: String) -> bool:
	if p.length() > 80 or p.contains("..") or p.contains("//"):
		return false
	for ch in p:
		if not ((ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in ["/", "-", "_", "."]):
			return false
	return true


## Ursprung (Schema, Host, Port) einer Adresse, "" wenn sie keiner ist.
static func origin_of(url: String) -> String:
	var u := url.strip_edges()
	var se := u.find("://")
	if se <= 0:
		return ""
	var rest := u.substr(se + 3)
	var cut := rest.length()
	for sep in ["/", "?", "#"]:
		var i := rest.find(sep)
		if i >= 0 and i < cut:
			cut = i
	var p := parse_server(u.substr(0, se + 3) + rest.substr(0, cut))
	return str(p.get("origin", ""))


## Adresse im Heimnetz (privat, link-lokal)? 127.x und ::1 nur in Tests mit nachgebautem Server.
static func is_private_ip(host: String) -> bool:
	var h := host.trim_prefix("[").trim_suffix("]").to_lower()
	if not h.is_valid_ip_address():
		return false
	if h.contains(":"):
		if h == "::1":
			return _loopback_ok()
		var first := h.get_slice(":", 0)
		if first.length() < 3:
			return false
		var v := first.hex_to_int()
		return (v & 0xfe00) == 0xfc00 or (v & 0xffc0) == 0xfe80
	var p := h.split(".")
	var a := int(p[0])
	var b := int(p[1])
	if a == 127:
		return _loopback_ok()
	return a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168) or (a == 169 and b == 254)


static func _loopback_ok() -> bool:
	return Config.probe_env("UZAI_TEST_LOOPBACK") == "1"


## Pfad, den ein Server für ein Bild oder eine Datei nennt („/library/metadata/1/thumb/2“):
## nur ein Pfad auf demselben Server, ohne Tricks (kein Schema, kein „..“, keine Steuerzeichen).
static func safe_path(p: Variant) -> String:
	var s := text(p, 600)
	if not s.begins_with("/") or s.begins_with("//") or s.contains("..") or s.contains("://") or s.contains("\\") or s.contains("@"):
		return ""
	for ch in s:
		if not ((ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")
				or ch in ["/", "-", "_", ".", "~", "%", "?", "=", "&", ":", ",", "+"]):
			return ""
	return s


## Volle Bildadresse fremder Herkunft nur von erlaubten Hosts (Plex: *.plex.tv) und nur https.
static func allowed_image(url: Variant, hosts: Array) -> String:
	var s := text(url, 600)
	var o := origin_of(s)
	if not s.begins_with("https://") or o == "":
		return ""
	var rest := s.substr(o.length())
	if rest != "" and safe_path(rest) == "":
		return ""
	var host := str(parse_server(o).get("host", ""))
	for h in hosts:
		if host == str(h) or host.ends_with("." + str(h)):
			return s
	return ""


# --- Kennungen der Quellen ---------------------------------------------------------------------

## Welcher Quelle gehört diese Kennung (Titel, Folge)? "" = keiner (dann den Addons).
static func owner_of(id: String) -> String:
	if id.begins_with("plex:"):
		return "plex"
	if id.begins_with("jf:"):
		return "jellyfin"
	if id.begins_with("emby:"):
		return "emby"
	return ""


## Welcher Quelle gehört ein Katalog („quelle:plex“)? "" = einem Addon.
static func owner_of_addon(addon_id: String) -> String:
	if not addon_id.begins_with("quelle:"):
		return ""
	var k := addon_id.substr(7)
	return k if k in ["plex", "jellyfin", "emby", "stremio"] else ""


# --- Altersfreigaben und Kinderfilter ----------------------------------------------------------

## Altersstufe zu einer Freigabe („de/12“, „FSK-16“, „PG-13“, „TV-MA“, „gb/15“). -1 = unbekannt.
static func age_of(rating: Variant) -> int:
	var s := text(rating, 40).to_upper().strip_edges()
	# Länderkürzel vorn („de/12“, „DE-12“, „UK-12A“) – aber nicht „TV-…“, „PG-…“, „NC-…“.
	if s.length() > 3 and s.substr(2, 1) in ["/", "-"] and s.substr(0, 2) not in ["TV", "PG", "NC"] and s.substr(0, 2).is_valid_identifier():
		s = s.substr(3)
	for pre in ["FSK", "USK", "FSF", "AB", "PEGI", "KIJKWIJZER"]:
		if s.begins_with(pre):
			s = s.substr(pre.length()).strip_edges().trim_prefix("-").trim_prefix(":").strip_edges()
	s = s.trim_suffix(" JAHREN").trim_suffix(" J.").strip_edges()
	if s in UNRATED:
		return -1
	if RATINGS.has(s):
		return int(RATINGS[s])
	var digits := ""
	for ch in s:
		if ch >= "0" and ch <= "9":
			digits += ch
		elif digits != "":
			break
	if digits == "" or digits.length() > 2:
		return -1
	return step_up(int(digits))


## Freigabe zum Anzeigen: „de/12“ wird „FSK 12“, sonst ohne Länderkürzel („PG-13“, „15“).
static func rating_label(rating: Variant) -> String:
	var s := text(rating, 24)
	if s.length() > 3 and s.substr(2, 1) == "/":
		var land := s.substr(0, 2).to_lower()
		s = s.substr(3)
		if land == "de" and s.is_valid_int():
			return "FSK " + s
	return s


## Auf die nächste Altersstufe aufrunden (7 → 12, 14 → 16).
static func step_up(age: int) -> int:
	for st in STEPS:
		if age <= int(st):
			return int(st)
	return 18


## Name einer Bibliothek oder eines Genres, das für Kinder und Familie steht.
static func family_word(name_: Variant) -> bool:
	var n := text(name_, 80).to_lower()
	for w in FAMILY_WORDS:
		if n == w or n.begins_with(w + " ") or n.ends_with(" " + w) or n.contains(" " + w + " ") or n.begins_with(w + "-") or n.ends_with("-" + w) \
				or n.begins_with(w + "&") or n.contains("& " + w) or n.contains(w + " &"):
			return true
	return false


## Darf ein Kinderprofil diesen Titel sehen? Mit Freigabe (age ≥ 0) zählt nur sie; ohne Freigabe
## nur Titel aus Kinder-/Familien-Bibliotheken oder mit Familien-Genre – oder alles, wenn die
## Eltern „Ohne Angabe erlauben“ eingeschaltet haben (rules.unknown, wie bei Spielen).
static func kid_allows(item: Dictionary, rules: Dictionary) -> bool:
	var age := num(item.get("age", -1), -1)
	if age >= 0:
		return age <= num(rules.get("age", 12), 12)
	if flag(item.get("family", false)) or bool(rules.get("unknown", false)):
		return true
	for g in arr(item.get("genres", []), 20):
		if family_word(g):
			return true
	return false


## Liste für ein Kinderprofil filtern (rules leer = kein Kinderprofil, alles bleibt).
static func kid_filter(list: Array, rules: Dictionary) -> Array:
	if rules.is_empty():
		return list
	return list.filter(func(it: Variant) -> bool: return it is Dictionary and kid_allows(it, rules))


## Reihen der Startseite für ein Kinderprofil: Titel filtern, leere Reihen fallen weg. Ordner
## eines Medienservers bleiben nur als Kinder-/Familien-Bibliothek; andere Ordner (Nuvio-
## Sammlungen) bleiben – ihre Seiten filtern beim Laden ohnehin jeden Titel.
static func kid_rows(rows: Array, rules: Dictionary) -> Array:
	if rules.is_empty():
		return rows
	var out: Array = []
	for r in rows:
		if not (r is Dictionary):
			continue
		if str(r.get("kind", "")) == "folders":
			var fs: Array = arr(r.get("folders", []), 200)
			if str(r.get("source", "")) != "":
				fs = fs.filter(func(f: Variant) -> bool: return f is Dictionary and flag(f.get("family", false)))
			if not fs.is_empty():
				var fr: Dictionary = (r as Dictionary).duplicate()
				fr["folders"] = fs
				out.append(fr)
			continue
		var items := kid_filter(r.get("items", []) if r.get("items") is Array else [], rules)
		if items.is_empty():
			continue
		var c: Dictionary = (r as Dictionary).duplicate()
		c["items"] = items
		out.append(c)
	return out

extends RefCounted
## Uzai-Browser (Wunschliste 120): Adressen prüfen und deuten – ohne Oberfläche, ohne Netz.
## Dieselben Regeln stehen im Browser-Wirt (helper/uzai-browser-wirt.cs, UzbRegeln.UrlGrund) – zwei
## Mauern, gleiches Urteil (Tabelle tests/fixtures/browser_urls.json, geprüft von tests/logic_browser.gd
## und tests/browser_cs.ps1):
##   - nur http und https, höchstens 4096 Zeichen, keine Steuer- oder Leerzeichen, keine Anmeldung in
##     der Adresse (user:pass@), Name nur aus Buchstaben, Ziffern, „-“, „_“ und „.“ (Punycode) oder eine IP;
##   - dieser PC (localhost, 127.0.0.0/8, ::1, 0.0.0.0) nie – dort lauschen Uzais eigene Anschlüsse;
##   - das Heimnetz (10/8, 172.16/12, 192.168/16, 169.254/16, 100.64/10, fc00::/7, fe80::/10) nur, wenn du die
##     Adresse selbst eingibst – nie über einen Link, eine Weiterleitung oder ein Skript einer Seite.
## deuten() macht aus dem, was du in die Adresszeile tippst, eine Adresse oder eine Suche.

const MAX_URL := 4096
const MAX_EINGABE := 2048

## Search engines to choose from (Menü › Suchmaschine). Only fixed https URLs; %s is the encoded query.
## The default is Google; Config migrates old settings that still hold the previous default once.
const SUCHMASCHINEN := [
	{ "id": "google", "name": "Google", "url": "https://www.google.com/search?q=%s" },
	{ "id": "duckduckgo", "name": "DuckDuckGo", "url": "https://duckduckgo.com/?q=%s" },
	{ "id": "startpage", "name": "Startpage", "url": "https://www.startpage.com/do/search?query=%s" },
	{ "id": "ecosia", "name": "Ecosia", "url": "https://www.ecosia.org/search?q=%s" },
	{ "id": "brave", "name": "Brave Search", "url": "https://search.brave.com/search?q=%s" },
	{ "id": "bing", "name": "Bing", "url": "https://www.bing.com/search?q=%s" },
]
const STANDARD_SUCHE := "google"

## Gründe, warum eine Adresse nicht geht ("" = in Ordnung). Dieselben Wörter meldet der Wirt.
const GRUENDE := ["protokoll", "laenge", "zeichen", "anmeldung", "name", "lokal", "heimnetz"]


## Warum diese Adresse nicht geöffnet wird ("" = in Ordnung). vom_nutzer: selbst eingetippt.
static func grund(url: Variant, vom_nutzer := false) -> String:
	if not (url is String):
		return "zeichen"
	var u: String = url
	if u.length() > MAX_URL or u.is_empty():
		return "laenge"
	for i in u.length():
		var c := u.unicode_at(i)
		if c <= 32 or c == 127 or c > 126:
			return "zeichen"
	var low := u.to_lower()
	var rest := ""
	if low.begins_with("https://"):
		rest = u.substr(8)
	elif low.begins_with("http://"):
		rest = u.substr(7)
	else:
		return "protokoll"
	var ende := rest.length()
	for z in ["/", "?", "#"]:
		var k := rest.find(z)
		if k >= 0 and k < ende:
			ende = k
	var autoritaet := rest.substr(0, ende)
	if autoritaet.contains("@"):
		return "anmeldung"
	if autoritaet.contains("\\"):
		return "zeichen"
	var hp := host_port(autoritaet)
	if hp.is_empty():
		return "name"
	var host: String = hp.host
	if ist_lokal(host):
		return "lokal"
	if ist_heimnetz(host) and not vom_nutzer:
		return "heimnetz"
	return ""


## Name und Anschluss aus „name:port“ bzw. „[v6]:port“ ({} wenn ungültig). Name klein geschrieben.
static func host_port(a: String) -> Dictionary:
	var host := ""
	var port := ""
	if a.begins_with("["):
		var zu := a.find("]")
		if zu < 0:
			return {}
		host = a.substr(0, zu + 1).to_lower()
		var hinten := a.substr(zu + 1)
		if hinten != "":
			if not hinten.begins_with(":"):
				return {}
			port = hinten.substr(1)
		if not _v6_ok(host.substr(1, host.length() - 2)):
			return {}
	else:
		var k := a.find(":")
		if k >= 0:
			host = a.substr(0, k).to_lower()
			port = a.substr(k + 1)
		else:
			host = a.to_lower()
		if not _name_ok(host):
			return {}
	if port != "":
		if not port.is_valid_int() or port.length() > 5 or port.begins_with("+") or port.begins_with("-"):
			return {}
		var p := port.to_int()
		if p < 1 or p > 65535:
			return {}
	return { "host": host, "port": port }


## Name: Teile aus a–z, 0–9, „_“ und „-“ (nicht am Rand), mit Punkt getrennt; höchstens 253 Zeichen.
## Ein Punkt am Ende ist erlaubt (voll qualifiziert) und zählt wie ohne.
static func _name_ok(h: String) -> bool:
	if h.is_empty() or h.length() > 253:
		return false
	var t := h.trim_suffix(".") if h.length() > 1 else h
	for teil in t.split("."):
		if teil.is_empty() or teil.length() > 63 or teil.begins_with("-") or teil.ends_with("-"):
			return false
		for ch in teil:
			if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-" or ch == "_"):
				return false
	return true


static func _v6_ok(s: String) -> bool:
	if s.length() < 2 or s.length() > 45:
		return false
	for ch in s:
		if not ((ch >= "0" and ch <= "9") or (ch >= "a" and ch <= "f") or ch == ":" or ch == "."):
			return false
	return s.contains(":") and not v6_gruppen(s).is_empty()


## Die acht Gruppen einer IPv6-Adresse (ohne Klammern, klein geschrieben) als Zahlen; [] wenn sie so nicht gilt.
## Jede Schreibweise derselben Adresse ergibt dieselben Gruppen („::1“, „0::1“, „::0001“, IPv4 am Ende als
## Punkte oder als zwei Gruppen). Geprüft wird danach an den Zahlen, nie am Text: Am Text ließ sich „dieser PC“
## umschreiben (0:0::ffff:7f00:1 ist 127.0.0.1).
static func v6_gruppen(s: String) -> Array:
	var t := s
	if t.contains("."):
		var k := t.rfind(":")
		var hinten := t.substr(k + 1)
		var v4 := ipv4(hinten) if k >= 0 and not hinten.ends_with(".") else []
		if v4.is_empty():
			return []
		t = t.substr(0, k + 1) + "%x:%x" % [int(v4[0]) * 256 + int(v4[1]), int(v4[2]) * 256 + int(v4[3])]
	var teile := t.split("::")
	if teile.size() > 2:
		return []
	var links := _v6_teil(teile[0])
	var rechts := _v6_teil(teile[1]) if teile.size() == 2 else []
	if links.has(-1) or rechts.has(-1):
		return []
	if teile.size() == 1:
		return links if links.size() == 8 else []
	# „::“ steht für mindestens eine Gruppe aus Nullen.
	if links.size() + rechts.size() > 7:
		return []
	var out := links.duplicate()
	for i in 8 - links.size() - rechts.size():
		out.append(0)
	out.append_array(rechts)
	return out


## Gruppen eines Stücks ohne „::“ („1:2:3“); [-1] wenn eine Gruppe nicht gilt.
static func _v6_teil(t: String) -> Array:
	var out: Array = []
	if t.is_empty():
		return out
	for p in t.split(":"):
		if p.is_empty() or p.length() > 4 or not p.is_valid_hex_number():
			return [-1]
		out.append(p.hex_to_int())
	return out


## IPv4 als vier Zahlen (nur die übliche Schreibweise; sonst []). Eine führende Null gilt nicht: Browser lesen
## „012“ als oktal (10) – 012.0.0.1 ist dort das Heimnetz, als Dezimalzahl gelesen sähe es öffentlich aus.
static func ipv4(h: String) -> Array:
	var t := h.trim_suffix(".")
	var teile := t.split(".")
	if teile.size() != 4:
		return []
	var out: Array = []
	for p in teile:
		if p.is_empty() or p.length() > 3 or not p.is_valid_int() or (p.length() > 1 and p.begins_with("0")):
			return []
		var n := p.to_int()
		if n < 0 or n > 255:
			return []
		out.append(n)
	return out


## Ein Name, der wie eine Zahl aussieht, aber keine übliche IPv4 ist (0x7f.1, 2130706433, 127.1):
## Browser deuten ihn als IP – Uzai lässt ihn gar nicht erst zu.
static func zahl_name(h: String) -> bool:
	var t := h.trim_suffix(".")
	var letzter := t.substr(t.rfind(".") + 1)
	if letzter.is_empty():
		return false
	if letzter.is_valid_int():
		return ipv4(t).is_empty()
	return letzter.begins_with("0x") and letzter.substr(2).is_valid_hex_number()


## Dieser PC: localhost (auch *.localhost), 127/8, 0.0.0.0, ::1, ::, IPv4 in IPv6 auf diese, Zahl-Namen.
static func ist_lokal(h: String) -> bool:
	var t := h.trim_suffix(".")
	if t == "localhost" or t.ends_with(".localhost"):
		return true
	if zahl_name(t):
		return true
	var v4 := ipv4(t)
	if not v4.is_empty():
		return v4[0] == 127 or v4[0] == 0
	if t.begins_with("["):
		var v6 := t.substr(1, t.length() - 2)
		var g := v6_gruppen(v6)
		# Nicht lesbar, oder IPv4 in Punkten darin: vorsichtshalber dieser PC.
		if g.is_empty() or v6.contains("."):
			return true
		# Über einen NAT64-Übergang (64:ff9b::/96) erreichbare IPv4-Adressen: ebenso.
		if g[0] == 0x64 and g[1] == 0xff9b:
			return true
		# ::, ::1 und jede IPv4 in IPv6 – in welcher Schreibweise auch immer: die ersten 80 Bit null, dann 0
		# (alte Form ::a.b.c.d) oder ffff (::ffff:a.b.c.d, auch als ::ffff:7f00:1).
		return g[0] == 0 and g[1] == 0 and g[2] == 0 and g[3] == 0 and g[4] == 0 and (g[5] == 0 or g[5] == 0xffff)
	return false


## Heimnetz: private, geteilte und Verbindungs-lokale Bereiche (IPv4 und IPv6).
static func ist_heimnetz(h: String) -> bool:
	var t := h.trim_suffix(".")
	var v4 := ipv4(t)
	if not v4.is_empty():
		var a: int = v4[0]
		var b: int = v4[1]
		return a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168) or (a == 169 and b == 254) \
				or (a == 100 and b >= 64 and b <= 127)
	if t.begins_with("["):
		var g := v6_gruppen(t.substr(1, t.length() - 2))
		if g.is_empty():
			return false
		# fc00::/7 (privat), fe80::/10 (Verbindung), fec0::/10 (alte Standort-Adressen) – an der ersten Gruppe.
		var g0: int = g[0]
		return (g0 & 0xfe00) == 0xfc00 or (g0 & 0xffc0) == 0xfe80 or (g0 & 0xffc0) == 0xfec0
	# Namen ohne Punkt (Router, NAS: „fritz.box“ hat einen) und die Heimnetz-Endungen.
	return not t.contains(".") or t.ends_with(".local") or t.ends_with(".lan") or t.ends_with(".home.arpa") or t.ends_with(".fritz.box") \
			or t == "fritz.box"


## Name der Seite für die Anzeige (ohne „www.“), "" wenn die Adresse nicht taugt.
static func host_von(url: String) -> String:
	var low := url.to_lower()
	var rest := url.substr(8) if low.begins_with("https://") else (url.substr(7) if low.begins_with("http://") else "")
	if rest == "":
		return ""
	var ende := rest.length()
	for z in ["/", "?", "#"]:
		var k := rest.find(z)
		if k >= 0 and k < ende:
			ende = k
	var hp := host_port(rest.substr(0, ende))
	if hp.is_empty():
		return ""
	var h: String = hp.host
	return h.substr(4) if h.begins_with("www.") else h


## Ist das eine verschlüsselte Adresse?
static func sicher(url: String) -> bool:
	return url.to_lower().begins_with("https://")


## Adresse ohne Sprungmarke (#…): Schlüssel für „Stelle je Seite“.
static func ohne_marke(url: String) -> String:
	var k := url.find("#")
	return url.substr(0, k) if k >= 0 else url


## Kurzer Schlüssel einer Seite (für gemerkte Stellen und Zoom): Hash der Adresse ohne Sprungmarke.
static func seiten_schluessel(url: String) -> String:
	return ohne_marke(url).sha256_text().substr(0, 16)


static func maschine(id: String) -> Dictionary:
	for m in SUCHMASCHINEN:
		if m.id == id:
			return m
	return SUCHMASCHINEN[0]


## Such-Adresse für einen Text mit der gewählten Suchmaschine.
static func such_url(text: String, maschine_id: String) -> String:
	var q := sauber(text, 512).strip_edges()
	return str(maschine(maschine_id).url).replace("%s", q.uri_encode())


## Alles, was sauber() herausnimmt oder zusammenfasst (auch zwei Leerzeichen hintereinander).
static var _RX_SCHMUTZ := RegEx.create_from_string(
		"[\\x{00}-\\x{1F}\\x{7F}-\\x{9F}\\x{200B}-\\x{200F}\\x{2028}-\\x{202E}\\x{2066}-\\x{2069}\\x{FEFF}\\x{FFF9}-\\x{FFFB}]|  ")


## Text aus fremden Quellen für die Anzeige: ohne Steuerzeichen, Richtungs- und unsichtbare Zeichen,
## Leerraum zusammengefasst, gekürzt.
static func sauber(v: Variant, max_len: int) -> String:
	if not (v is String):
		return ""
	var s: String = v
	if s.length() > max_len * 4:
		s = s.left(max_len * 4)
	# Fast immer ist nichts zu säubern: dann ein Suchlauf der Engine statt Zeichen für Zeichen im Skript (der
	# Lesemodus schickt bis zu 200 Absätze).
	if _RX_SCHMUTZ.search(s) == null:
		return s.strip_edges().left(max_len)
	var out := PackedStringArray()
	var leer := false
	for ch in s:
		var c := ch.unicode_at(0)
		if c < 32 or c == 127 or (c >= 0x80 and c < 0xA0) or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) \
				or (c >= 0x2066 and c <= 0x2069) or c == 0xFEFF or c == 0x2028 or c == 0x2029 or (c >= 0xFFF9 and c <= 0xFFFB):
			if c == 9 or c == 10 or c == 13:
				if not leer:
					out.append(" ")
					leer = true
			continue
		if ch == " ":
			if leer:
				continue
			leer = true
		else:
			leer = false
		out.append(ch)
	var t := "".join(out).strip_edges()
	return t.left(max_len)


## Was in der Adresszeile steht, als Adresse oder Suche: { url, art: "adresse" | "suche", grund }.
## Leer: {}. Eine Adresse, die nicht geht, kommt mit grund zurück (Uzai sagt dann, warum).
static func deuten(eingabe: String, maschine_id := STANDARD_SUCHE) -> Dictionary:
	var t := sauber(eingabe, MAX_EINGABE)
	if t.is_empty():
		return {}
	var low := t.to_lower()
	if low.begins_with("http://") or low.begins_with("https://"):
		return { "url": t, "art": "adresse", "grund": grund(t, true) }
	# Andere Schemata (javascript:, file:, steam:) nie als Adresse – als Suche ist es harmlos.
	if " " in t or not _sieht_wie_adresse(t):
		return { "url": such_url(t, maschine_id), "art": "suche", "grund": "" }
	var url := "https://" + t
	# Heimnetz-Namen und IPs ohne Zertifikat: wer sie selbst eingibt, meint meist http.
	var ende := t.length()
	for z in ["/", "?", "#"]:
		var k := t.find(z)
		if k >= 0 and k < ende:
			ende = k
	var hp := host_port(t.substr(0, ende))
	if not hp.is_empty() and (ist_heimnetz(str(hp.host)) or not ipv4(str(hp.host)).is_empty()):
		url = "http://" + t
	return { "url": url, "art": "adresse", "grund": grund(url, true) }


## Sieht der Text wie eine Adresse aus? Name mit Punkt und Endung aus Buchstaben (2–24), eine IP oder
## ein Name mit Anschluss – sonst ist es eine Suche („wetter morgen“, „c++“).
static func _sieht_wie_adresse(t: String) -> bool:
	if t.contains("://") or t.begins_with("/") or t.contains("\\"):
		return false
	var ende := t.length()
	for z in ["/", "?", "#"]:
		var k := t.find(z)
		if k >= 0 and k < ende:
			ende = k
	var a := t.substr(0, ende)
	if a.contains("@"):
		return false
	var hp := host_port(a)
	if hp.is_empty():
		return false
	var h: String = str(hp.host).trim_suffix(".")
	if h.begins_with("[") or not ipv4(h).is_empty():
		return true
	if not h.contains("."):
		return str(hp.port) != ""
	var endung := h.substr(h.rfind(".") + 1)
	if endung.length() < 2 or endung.length() > 24:
		return false
	if endung.begins_with("xn--"):
		return true
	for ch in endung:
		if not (ch >= "a" and ch <= "z"):
			return false
	return true

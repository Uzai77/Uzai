extends RefCounted
## Einladungslink fürs Zimmer (Punkt 131; docs/ZIMMER_SICHERHEIT.md W3 und Abschnitt 5).
## Eine zufällige Zimmer-Kennung (128 Bit) und ein zufälliger Schlüssel (256 Bit) stehen nur im
## Link-Teil hinter „#“ – den schickt kein Browser an einen Server, und Uzai schreibt ihn in kein Log.
##
##   uzai://zimmer#z1.<Kennung base64url, 22 Zeichen>.<Schlüssel base64url, 43 Zeichen>
##
## Der Link selbst trägt keine Ablaufzeit (die ließe sich fälschen): Gültigkeit, „nur einmal“ und
## Zurückziehen prüft der Gastgeber an seiner eigenen Liste. Ein gültiger Link erlaubt nur das
## Anklopfen – herein kommt nur, wen der Gastgeber annimmt. Zufall aus Crypto (mbedTLS CTR_DRBG,
## vom Betriebssystem gesät); verglichen wird ohne Zeit-Leck (constant_time_compare).

const PRAEFIX := "uzai://zimmer#"
const FORM := "z1"
const KENNUNG_BYTES := 16
const SCHLUESSEL_BYTES := 32
const MAX_LINK := 128
const GUELTIG_MIN := [15, 60, 1440]  ## wählbar: 15 Minuten, 1 Stunde, 1 Tag
const B64URL := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"


## Neue Einladung (nur beim Gastgeber gespeichert). jetzt in Unix-Sekunden.
static func neu(jetzt: int, minuten: int, einmalig: bool) -> Dictionary:
	var c := Crypto.new()
	return {
		"kennung": c.generate_random_bytes(KENNUNG_BYTES),
		"schluessel": c.generate_random_bytes(SCHLUESSEL_BYTES),
		"ab": jetzt,
		"bis": jetzt + (minuten if minuten in GUELTIG_MIN else 60) * 60,
		"einmalig": einmalig,
		"benutzt": false,
	}


static func link(e: Dictionary) -> String:
	return PRAEFIX + FORM + "." + b64url(e.kennung) + "." + b64url(e.schluessel)


## Link (oder nur der Teil hinter „#“) → { kennung, schluessel } oder {}. Streng: genau diese Form,
## genau diese Längen, nur das base64url-Alphabet, kanonisch (keine Füllbits).
static func lesen(s: String) -> Dictionary:
	if s.length() > MAX_LINK:
		return {}
	var frag := s
	if s.begins_with(PRAEFIX):
		frag = s.substr(PRAEFIX.length())
	elif s.contains("#") or s.contains(":") or s.contains("/"):
		return {}
	var teile := frag.split(".", true)
	if teile.size() != 3 or teile[0] != FORM:
		return {}
	var k := b64url_lesen(teile[1], KENNUNG_BYTES)
	var sch := b64url_lesen(teile[2], SCHLUESSEL_BYTES)
	if k.is_empty() or sch.is_empty():
		return {}
	return { "kennung": k, "schluessel": sch }


## Darf mit dieser Einladung gerade jemand anklopfen?
static func gueltig(e: Dictionary, jetzt: int) -> bool:
	if jetzt < int(e.get("ab", 0)) or jetzt >= int(e.get("bis", 0)):
		return false
	return not (bool(e.get("einmalig", false)) and bool(e.get("benutzt", false)))


## Gehört der Schlüssel zu dieser Einladung? Vergleich ohne Zeit-Leck.
static func passt(e: Dictionary, schluessel: PackedByteArray) -> bool:
	var eigen: PackedByteArray = e.get("schluessel", PackedByteArray())
	if eigen.size() != SCHLUESSEL_BYTES or schluessel.size() != SCHLUESSEL_BYTES:
		return false
	return Crypto.new().constant_time_compare(eigen, schluessel)


static func b64url(b: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(b).replace("+", "-").replace("/", "_").replace("=", "")


## base64url ohne Füllzeichen → genau n Bytes, sonst leer.
static func b64url_lesen(s: String, n: int) -> PackedByteArray:
	if s.length() != ceili(n * 4.0 / 3.0):
		return PackedByteArray()
	for ch in s:
		if not B64URL.contains(ch):
			return PackedByteArray()
	var std := s.replace("-", "+").replace("_", "/")
	while std.length() % 4 != 0:
		std += "="
	var b := Marshalls.base64_to_raw(std)
	if b.size() != n or b64url(b) != s:
		return PackedByteArray()
	return b


# --- Einladungscode (Freundestest: zum Abtippen, als QR-Code, per Zwischenablage) -----------------------
## Kurz und gut lesbar statt des langen Links: 35 Zeichen Crockford-Base32 (ohne I, L, O, U – nichts zum
## Verwechseln) in sieben Fünfergruppen, davor „UZAI-“:
##
##   UZAI-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX
##
## Inhalt (160 Bit = 32 Zeichen): Geheimnis 18 Byte (144 Bit Zufall, Mindestmaß 128) und das Ablauf-Minute
## (u16, Unix-Minute mod 65536). Kennung und Schlüssel des Postfachs kommen per HKDF-SHA256 (RFC 5869, HMAC aus
## Godot/mbedTLS) aus beidem: Wer die Ablaufzeit im Code ändert, landet in einem fremden, leeren Postfach. Die
## Ablaufzeit liest der Gast nur, um ehrlich „abgelaufen“ zu sagen – entscheiden tut der Gastgeber an seiner
## eigenen Liste (gueltig). Prüfzeichen (3 Zeichen, 15 Bit): gewichtete Summe mod 1021 (findet JEDEN Tippfehler
## in einem Zeichen und jeden Dreher zweier Nachbarn) und 5 Bit aus SHA-256. Fremder Text wird nur gelesen:
## erst die Länge, dann Zeichen für Zeichen gegen das Alphabet – nie ausgeführt, nie als Link geöffnet.

const CODE_PRAEFIX := "UZAI"
const CODE_ZEICHEN := 35
const CODE_GEHEIM := 18
const CODE_MAX_EINGABE := 120        ## längere Eingaben werden gar nicht erst angesehen
const CODE_SPIEL_MIN := 3            ## so viele Minuten darf die Uhr des Gastes nachgehen
const B32 := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const KDF_SALZ := "UZ-einladung-1"


## Neue Einladung mit Code (nur beim Gastgeber gespeichert, immer einmalig). Die Ablaufzeit fällt auf eine
## volle Minute (die steht im Code).
static func neu_code(jetzt: int, minuten: int) -> Dictionary:
	var m := minuten if minuten in GUELTIG_MIN else 60
	var bis_min := ceili((jetzt + m * 60) / 60.0)
	var geheim := Crypto.new().generate_random_bytes(CODE_GEHEIM)
	var inhalt := geheim.duplicate()
	inhalt.append(bis_min & 0xFF)
	inhalt.append((bis_min >> 8) & 0xFF)
	var ks := _ableiten(inhalt)
	return {
		"kennung": ks[0], "schluessel": ks[1], "ab": jetzt, "bis": bis_min * 60, "einmalig": true, "benutzt": false,
		"code": _code_aus(inhalt),
	}


## Der Code zum Anzeigen (mit Bindestrichen).
static func code_anzeige(code: String) -> String:
	var g: PackedStringArray = [CODE_PRAEFIX]
	for i in range(0, code.length(), 5):
		g.append(code.substr(i, 5))
	return "-".join(g)


## Eingabe (abgetippt oder aus der Zwischenablage) → { ok, fehler, kennung, schluessel, rest_min }.
## fehler: "leer", "lang", "zeichen", "laenge", "pruefsumme", "abgelaufen", "zeit" (Ablauf unplausibel weit weg).
## Erlaubt sind nur Leerraum, Bindestriche, das Präfix und die 32 Zeichen (klein wie groß, O = 0, I und L = 1).
static func code_lesen(s: Variant, jetzt: int) -> Dictionary:
	var r := { "ok": false, "fehler": "leer", "kennung": PackedByteArray(), "schluessel": PackedByteArray(), "rest_min": 0 }
	if not (s is String) or (s as String).strip_edges() == "":
		return r
	var t: String = s
	if t.length() > CODE_MAX_EINGABE:
		r.fehler = "lang"
		return r
	var roh := ""
	for i in t.length():
		var c := t.unicode_at(i)
		if c == 32 or c == 9 or c == 10 or c == 13 or c == 45:
			continue
		if c >= 97 and c <= 122:
			c -= 32
		if c < 48 or c > 90:
			r.fehler = "zeichen"
			return r
		roh += char(c)
	if roh.begins_with(CODE_PRAEFIX) and roh.length() == CODE_PRAEFIX.length() + CODE_ZEICHEN:
		roh = roh.substr(CODE_PRAEFIX.length())
	if roh.length() != CODE_ZEICHEN:
		r.fehler = "laenge"
		return r
	var werte := PackedInt32Array()
	for ch in roh:
		var v := _b32_wert(ch)
		if v < 0:
			r.fehler = "zeichen"
			return r
		werte.append(v)
	var inhalt := _bits_zu_bytes(werte.slice(0, 32))
	if inhalt.size() != CODE_GEHEIM + 2 or _pruef(werte.slice(0, 32), inhalt) != werte.slice(32):
		r.fehler = "pruefsumme"
		return r
	var bis_min := inhalt[CODE_GEHEIM] | (inhalt[CODE_GEHEIM + 1] << 8)
	var diff := (bis_min - (jetzt / 60)) & 0xFFFF
	var rest := diff if diff < 0x8000 else diff - 0x10000
	if rest < -CODE_SPIEL_MIN:
		r.fehler = "abgelaufen"
		return r
	if rest > int(GUELTIG_MIN.max()) + CODE_SPIEL_MIN:
		r.fehler = "zeit"
		return r
	var ks := _ableiten(inhalt)
	r.ok = true
	r.fehler = ""
	r.kennung = ks[0]
	r.schluessel = ks[1]
	r.rest_min = maxi(0, rest)
	return r


## HKDF-SHA256 (RFC 5869): Extract mit festem Salz, Expand je Zweck ein Block.
static func _ableiten(inhalt: PackedByteArray) -> Array:
	var c := Crypto.new()
	var prk := c.hmac_digest(HashingContext.HASH_SHA256, KDF_SALZ.to_utf8_buffer(), inhalt)
	var k := c.hmac_digest(HashingContext.HASH_SHA256, prk, "kennung".to_utf8_buffer() + PackedByteArray([1]))
	var s := c.hmac_digest(HashingContext.HASH_SHA256, prk, "schluessel".to_utf8_buffer() + PackedByteArray([1]))
	return [k.slice(0, KENNUNG_BYTES), s]


static func _code_aus(inhalt: PackedByteArray) -> String:
	var werte := _bytes_zu_bits(inhalt)
	werte.append_array(_pruef(werte, inhalt))
	var out := ""
	for v in werte:
		out += B32[v]
	return out


## Drei Prüfzeichen: gewichtete Summe mod 1021 (10 Bit; Gewichte 1 … 32 sind verschieden und kleiner als die
## Primzahl – jeder Fehler in einem Zeichen und jeder Nachbar-Dreher ändert die Summe) und 5 Bit aus SHA-256.
static func _pruef(werte: PackedInt32Array, inhalt: PackedByteArray) -> PackedInt32Array:
	var summe := 0
	for i in werte.size():
		summe = (summe + (i + 1) * werte[i]) % 1021
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update("UZ-pruef-1".to_utf8_buffer() + inhalt)
	return PackedInt32Array([summe >> 5, summe & 31, h.finish()[0] >> 3])


static func _b32_wert(ch: String) -> int:
	match ch:
		"O":
			return 0
		"I", "L":
			return 1
	return B32.find(ch)


static func _bytes_zu_bits(b: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	var akku := 0
	var n := 0
	for x in b:
		akku = (akku << 8) | x
		n += 8
		while n >= 5:
			n -= 5
			out.append((akku >> n) & 31)
		akku &= (1 << n) - 1
	if n > 0:
		out.append((akku << (5 - n)) & 31)
	return out


## 32 Zeichen → genau 20 Byte (160 Bit, keine Füllbits).
static func _bits_zu_bytes(w: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	var akku := 0
	var n := 0
	for v in w:
		akku = (akku << 5) | v
		n += 5
		if n >= 8:
			n -= 8
			out.append((akku >> n) & 0xFF)
			akku &= (1 << n) - 1
	return out if n == 0 else PackedByteArray()


# --- Einladung im Chat (an einen Steam- oder Discord-Freund) ---------------------------------------------

const CHAT_MAX := 400          ## nur so viel einer Nachricht sieht Uzai an
const CHAT_SATZ := "Komm in mein Zimmer in Uzai. Code: %s"


## Was Uzai einem Freund schickt: ein kurzer Satz und der Code – sonst nichts (kein Link, kein Name).
static func chat_text(code: String) -> String:
	return TranslationServer.translate(CHAT_SATZ) % code_anzeige(code)


## Einladung in einer Chat-Nachricht finden. Nur lesen: Der Text wird nie ausgeführt, geöffnet oder als
## Adresse behandelt. Der Code muss als Ganzes dastehen („UZAI“ und 35 Zeichen, dazwischen nur
## Bindestriche und Leerzeichen) und besteht dieselbe strenge Prüfung wie ein eingetippter (code_lesen).
## { ok, code (35 Zeichen, bereinigt), rest_min, fehler } – fehler: "keiner" (kein Code im Text) oder
## wie code_lesen ("pruefsumme", "abgelaufen" …).
static func code_im_text(text: Variant, jetzt: int) -> Dictionary:
	var r := { "ok": false, "code": "", "rest_min": 0, "fehler": "keiner" }
	if not (text is String):
		return r
	var gross := (text as String).left(CHAT_MAX).to_upper()
	var ab := 0
	for versuch in 3:
		var i := gross.find(CODE_PRAEFIX, ab)
		if i < 0:
			break
		ab = i + CODE_PRAEFIX.length()
		var roh := ""
		var j := ab
		while j < gross.length() and roh.length() < CODE_ZEICHEN and j - ab < CODE_ZEICHEN + 12:
			var ch := gross[j]
			j += 1
			if ch == "-" or ch == " ":
				continue
			var w := _b32_wert(ch)
			if w < 0:
				break
			roh += B32[w]
		# Zu kurz – oder der Code ginge in einem längeren Wort weiter: kein Code.
		if roh.length() != CODE_ZEICHEN or (j < gross.length() and _b32_wert(gross[j]) >= 0):
			continue
		var l := code_lesen(CODE_PRAEFIX + roh, jetzt)
		if bool(l.ok):
			return { "ok": true, "code": roh, "rest_min": int(l.rest_min), "fehler": "" }
		r.fehler = str(l.fehler)
	return r

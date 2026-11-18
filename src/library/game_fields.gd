extends RefCounted
## Eigene Angaben je Spiel (Roadmap 41, 42) und Änderungen an vielen Spielen auf einmal. Rechnet
## nur: keine Knoten, kein Netz. Alles liegt am Spiel in library.json (Library.USER_FIELDS), kommt
## so in jede Sicherung und bleibt beim Einlesen stehen.
##   tags      ["Koop", "Couch"] – frei, höchstens TAGS_MAX; ein Tag, den es schon gibt, behält
##             seine Schreibung („koop“ wird zu „Koop“)
##   category  „Sammlung“ – eine je Spiel
##   age       Altersfreigabe, Kennung aus AGES („usk16“)
##   region    Region der Fassung, Kennung aus REGIONS („pal“)
##   links     [{ name, url }] – nur https. Uzai zeigt sie als QR-Code fürs Handy und öffnet sie nie
##             selbst (kein Browser, kein Wechsel aus Uzai heraus).

const FIELDS := ["tags", "category", "age", "region", "links"]
const AGES := [["usk0", "USK 0"], ["usk6", "USK 6"], ["usk12", "USK 12"], ["usk16", "USK 16"], ["usk18", "USK 18"],
	["pegi3", "PEGI 3"], ["pegi7", "PEGI 7"], ["pegi12", "PEGI 12"], ["pegi16", "PEGI 16"], ["pegi18", "PEGI 18"]]
## [Kennung, Name, wo die Fassung herkommt]
const REGIONS := [["pal", "PAL", "Europa, Australien"], ["ntsc-u", "NTSC-U", "Nordamerika"], ["ntsc-j", "NTSC-J", "Japan"],
	["ntsc-k", "NTSC-K", "Korea"], ["frei", "Regionsfrei", "läuft überall"]]
const TAG_MAX := 32
const TAGS_MAX := 20
const CATEGORY_MAX := 40
const LINKS_MAX := 8
const LINK_NAME_MAX := 40
const URL_MAX := 500
## Was viele Spiele auf einmal ändern kann (apply_op).
const OPS := ["tag_add", "tag_remove", "category", "age", "region", "fav", "hidden", "folder_add", "folder_remove"]


# --- Text ------------------------------------------------------------------------------------

## Eingabe säubern: keine Steuerzeichen (Zeilenumbrüche, Tabs), Leerraum zusammengefasst, gekürzt.
static func clean_text(s: String, max_len: int) -> String:
	var out := ""
	var space := false
	for ch in s:
		var c := ch.unicode_at(0)
		if c < 32 or c == 127 or ch == " " or ch == " ":
			space = out != ""
			continue
		if space:
			out += " "
			space = false
		out += ch
	return out.left(max_len).strip_edges()


static func age_label(key: String) -> String:
	return _label(AGES, key)


static func region_label(key: String) -> String:
	return _label(REGIONS, key)


static func _label(list: Array, key: String) -> String:
	for e in list:
		if e[0] == key:
			return str(e[1])
	return ""


# --- Tags und Kategorie ----------------------------------------------------------------------

static func tags_of(g: Dictionary) -> PackedStringArray:
	var v: Variant = g.get("tags")
	return PackedStringArray(v) if v is Array or v is PackedStringArray else PackedStringArray()


static func category_of(g: Dictionary) -> String:
	return str(g.get("category", "")) if g.get("category") is String else ""


## Tags aller Spiele mit Anzahl: { Schreibung: n }. Gleiche Tags in anderer Groß-/Kleinschreibung
## zählen zusammen unter der zuerst gefundenen Schreibung.
static func all_tags(list: Array) -> Dictionary:
	var out := {}
	var spell := {}
	for g in list:
		for t in tags_of(g):
			var k := t.to_lower()
			if not spell.has(k):
				spell[k] = t
			out[spell[k]] = int(out.get(spell[k], 0)) + 1
	return out


static func categories(list: Array) -> Dictionary:
	var out := {}
	var spell := {}
	for g in list:
		var c := category_of(g)
		if c == "":
			continue
		var k := c.to_lower()
		if not spell.has(k):
			spell[k] = c
		out[spell[k]] = int(out.get(spell[k], 0)) + 1
	return out


## Namen nach Häufigkeit, bei Gleichstand nach dem Alphabet (Vorschläge, Auswahl).
static func by_count(counts: Dictionary) -> Array:
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b): return int(counts[a]) > int(counts[b]) if counts[a] != counts[b] else str(a).naturalnocasecmp_to(str(b)) < 0)
	return keys


## Die Schreibung, unter der es den Text schon gibt („koop“ → „Koop“), sonst der Text selbst.
static func known_spelling(t: String, known: Variant) -> String:
	var k := t.to_lower()
	for x in known:
		if str(x).to_lower() == k:
			return str(x)
	return t


## Tags mit einem weiteren (gesäubert, ohne Doppelte, höchstens TAGS_MAX). known: vorhandene Tags.
static func with_tag(tags: Variant, t: String, known: Variant = []) -> Array:
	var out: Array = Array(tags).duplicate() if tags is Array or tags is PackedStringArray else []
	var c := known_spelling(clean_text(t, TAG_MAX), known)
	if c == "" or out.size() >= TAGS_MAX or out.any(func(x): return str(x).to_lower() == c.to_lower()):
		return out
	out.append(c)
	return out


static func without_tag(tags: Variant, t: String) -> Array:
	var out: Array = Array(tags) if tags is Array or tags is PackedStringArray else []
	return out.filter(func(x): return str(x).to_lower() != t.to_lower())


# --- Links -----------------------------------------------------------------------------------

## Warum ein Link nicht geht ("" = gut): nur https, mit Adresse, ohne Leerzeichen, Steuerzeichen
## oder Anmeldedaten vor der Adresse („https://bank.de@böse.example“ täuscht ein anderes Ziel vor).
static func link_problem(url: String) -> String:
	if url == "":
		return "Kein Link eingegeben."
	if url.length() > URL_MAX:
		return "Der Link ist zu lang (höchstens %d Zeichen)." % URL_MAX
	if not url.to_lower().begins_with("https://"):
		return "Nur sichere Links mit https:// – andere nimmt Uzai nicht an."
	for ch in url:
		var c := ch.unicode_at(0)
		if c <= 32 or c == 127 or ch == "\\":
			return "Im Link stehen Leerzeichen oder Zeichen, die dort nicht hingehören."
	var auth := url.substr(8).get_slice("/", 0).get_slice("?", 0).get_slice("#", 0)
	if auth.contains("@"):
		return "Links mit Anmeldedaten vor der Adresse nimmt Uzai nicht an."
	var host := auth.get_slice(":", 0)
	if host.length() < 3 or not host.contains(".") or host.begins_with(".") or host.ends_with("."):
		return "Nach https:// fehlt eine richtige Adresse."
	return ""


## Adresse ohne „www.“ – so steht der Link, wenn er keinen eigenen Namen hat.
static func host_of(url: String) -> String:
	return url.substr(8).get_slice("/", 0).get_slice("?", 0).get_slice("#", 0).get_slice(":", 0).to_lower().trim_prefix("www.")


static func link_title(l: Dictionary) -> String:
	var n := str(l.get("name", ""))
	return n if n != "" else host_of(str(l.get("url", "")))


## Gültige Links eines Spiels (was nicht passt, fällt weg).
static func links_of(g: Dictionary) -> Array:
	var out: Array = []
	var v: Variant = g.get("links")
	if not (v is Array):
		return out
	for l in v:
		if l is Dictionary and l.get("url") is String and link_problem(str(l.url)) == "":
			out.append({ "name": clean_text(str(l.get("name", "")), LINK_NAME_MAX), "url": str(l.url) })
		if out.size() >= LINKS_MAX:
			break
	return out


# --- Laden -----------------------------------------------------------------------------------

## Beim Laden: nur, was zu den Feldern passt (library.json kann von Hand geändert oder von einer
## anderen Version sein). Ein Link, der kein https ist, kommt so nie bis in die Oberfläche.
static func sanitize(g: Dictionary) -> void:
	if g.has("tags"):
		var t: Array = []
		var raw: Variant = g.get("tags")
		for x in (raw if raw is Array else []):
			if x is String:
				t = with_tag(t, x, t)
		_put(g, "tags", t if not t.is_empty() else null)
	if g.has("category"):
		var c := clean_text(str(g.category), CATEGORY_MAX) if g.get("category") is String else ""
		_put(g, "category", c if c != "" else null)
	if g.has("age") and age_label(str(g.age)) == "":
		g.erase("age")
	if g.has("region") and region_label(str(g.region)) == "":
		g.erase("region")
	if g.has("links"):
		var l := links_of(g)
		_put(g, "links", l if not l.is_empty() else null)


static func _put(g: Dictionary, k: String, v: Variant) -> void:
	if v == null:
		g.erase(k)
	else:
		g[k] = v


# --- Viele Spiele auf einmal -----------------------------------------------------------------

## Eine Änderung an einem Spiel. true, wenn sich etwas geändert hat (sonst bleibt es, wie es war).
##   tag_add / tag_remove   value: Tag
##   category / age / region value: Text bzw. Kennung, "" entfernt
##   fav / hidden            value: true/false
##   folder_add / _remove    value: Ordner { id, system } – nur, wenn er zum System passt
static func apply_op(g: Dictionary, op: String, value: Variant, known: Variant = []) -> bool:
	match op:
		"tag_add", "tag_remove":
			var before := tags_of(g)
			var after: Array = with_tag(before, str(value), known) if op == "tag_add" else without_tag(before, str(value))
			if after == Array(before):
				return false
			_put(g, "tags", after if not after.is_empty() else null)
			return true
		"category":
			var c := known_spelling(clean_text(str(value), CATEGORY_MAX), known)
			if c == category_of(g):
				return false
			_put(g, "category", c if c != "" else null)
			return true
		"age", "region":
			var k := str(value)
			if k != "" and (age_label(k) if op == "age" else region_label(k)) == "":
				return false
			if k == str(g.get(op, "")):
				return false
			_put(g, op, k if k != "" else null)
			return true
		"fav", "hidden":
			var key := "favorite" if op == "fav" else "hidden"
			if bool(value) == bool(g.get(key, false)):
				return false
			_put(g, key, true if value else null)
			return true
		"folder_add", "folder_remove":
			if not (value is Dictionary) or str(value.get("id", "")) == "" or str(value.id).begins_with("auto:"):
				return false
			var fid := str(value.id)
			var fl: Array = (g.get("folders", []) as Array).duplicate() if g.get("folders") is Array else []
			if op == "folder_add":
				if fl.has(fid) or not folder_fits(g, value):
					return false
				fl.append(fid)
			else:
				if not fl.has(fid):
					return false
				fl.erase(fid)
			_put(g, "folders", fl if not fl.is_empty() else null)
			return true
	return false


## Passt ein Ordner zu einem Spiel? Ordner für alle Systeme immer, sonst nur das eigene System.
static func folder_fits(g: Dictionary, f: Dictionary) -> bool:
	var sys := str(f.get("system", ""))
	return sys == "" or sys == str(g.get("system", ""))


## Wie viele Spiele eine Änderung wirklich träfe (für die Rückfrage), ohne etwas zu ändern.
static func op_count(list: Array, op: String, value: Variant, known: Variant = []) -> int:
	var n := 0
	for g in list:
		if apply_op((g as Dictionary).duplicate(true), op, value, known):
			n += 1
	return n

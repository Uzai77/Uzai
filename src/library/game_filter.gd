extends RefCounted
## Filter und Abschnitte für das Spiele-Raster (Roadmap 39, 40). Rechnet nur: keine Knoten, kein
## Netz. Das Raster gibt seine Spiele hinein und bekommt Abschnitte mit Überschrift zurück.
## Was ein Spiel nicht hergibt (Genre und Jahr bei Emulator-, Epic- und EA-Spielen), steht ehrlich
## unter „Unbekannt“ – geraten wird nichts. Genre und Jahr kommen aus dem Steam-Shop und liegen
## am Spiel (Library.remember_store_meta).
##
## Ein Filter ist ein Dictionary mit nur den gesetzten Feldern; alle zusammen müssen passen:
##   platform   "steam", "epic", "ea", "pc" oder die System-ID eines Emulators („ps2“)
##   installed  "ja" | "nein"
##   played     "ja" | "nein"
##   fav        true
##   genre      Name des Genres, "?" = ohne Angabe
##   decade     1990, 2000, …; -1 = ohne Angabe
##   time       "lt1" | "1-10" | "10-50" | "gt50" (Spielzeit in Stunden)
##   ach        "mit" | "offen" | "komplett" (nur, was Uzai über die Erfolge schon weiß)
##   tag        eigener Tag (Groß-/Kleinschreibung egal), "?" = ohne Tag     (Roadmap 41, game_fields.gd)
##   category   eigene Kategorie, "?" = ohne
##   age        Altersfreigabe („usk16“), "?" = ohne Angabe
##   region     Region („pal“), "?" = ohne Angabe
##   status     Backlog-Status („spiele“), "?" = ohne Status                   (Roadmap 2, backlog.gd)
##   stars      Bewertung: "5", "ge4", "ge3", "lt3", "?" = ohne Bewertung

const GameFields := preload("res://src/library/game_fields.gd")
const Stores := preload("res://src/library/stores.gd")
const Backlog := preload("res://src/library/backlog.gd")

const GROUPS := [["", "Keine Abschnitte"], ["platform", "Nach Plattform"], ["genre", "Nach Genre"], ["series", "Nach Spielreihe"],
	["decade", "Nach Jahrzehnt"], ["year", "Nach Erscheinungsjahr"], ["category", "Nach Kategorie"], ["tag", "Nach Tag"],
	["age", "Nach Altersfreigabe"], ["region", "Nach Region"], ["status", "Nach Backlog-Status"], ["stars", "Nach Bewertung"]]
## Abschnitte aus eigenen Angaben: nur anbieten, wenn mindestens ein Spiel eine hat.
const OWN_GROUPS := ["category", "tag", "age", "region", "status", "stars"]
const TIMES := [["lt1", "Unter 1 Std."], ["1-10", "1 bis 10 Std."], ["10-50", "10 bis 50 Std."], ["gt50", "Über 50 Std."]]
const ACH := [["mit", "Mit Erfolgen"], ["offen", "Erfolge offen"], ["komplett", "Alle Erfolge geholt"]]
const UNKNOWN := "Unbekannt"
const NO_SERIES := "Einzelne Spiele"
const NO_TAG := "Ohne Tag"
const NO_CATEGORY := "Ohne Kategorie"
const PRESETS_MAX := 24
const NAME_MAX := 40
const _CACHE_MAX := 20000

## Beim Laden gefüllt, danach nur gelesen (nie beim ersten Aufruf anlegen: Ein zweiter Faden sähe sie halb fertig).
static var _re_year := RegEx.create_from_string("\\b(19[5-9]\\d|20\\d\\d)\\b")
static var _re_tail := RegEx.create_from_string("\\s+(\\d{1,4}|[IVX]{1,5})$")
static var _re_edition := RegEx.create_from_string("(?i)\\s+(hd|remastered|remaster|remake|goty|director's cut|game of the year edition|[\\w']+ edition)$")
static var _series := {}           ## Titel → Name der Reihe (Titel wiederholen sich bei jedem Füllen)


# --- Filtern ---------------------------------------------------------------------------------

## Nur die Spiele, die zum Filter passen (Reihenfolge bleibt). ach: Spiel-ID → [frei, gesamt].
static func apply(list: Array, f: Dictionary, ach := {}) -> Array:
	if f.is_empty():
		return list
	var out: Array = []
	for g in list:
		if matches(g, f, ach):
			out.append(g)
	return out


static func matches(g: Dictionary, f: Dictionary, ach := {}) -> bool:
	if f.has("platform") and not (str(f.platform) in platforms_of(g)):
		return false
	if f.has("installed") and Library.is_installed(g) != (str(f.installed) == "ja"):
		return false
	if f.has("played") and played(g) != (str(f.played) == "ja"):
		return false
	if f.get("fav", false) and not bool(g.get("favorite", false)):
		return false
	if f.has("genre"):
		var gen := genres_of(g)
		if str(f.genre) == "?" and not gen.is_empty():
			return false
		if str(f.genre) != "?" and not gen.has(str(f.genre)):
			return false
	if f.has("decade") and decade_of(g) != int(f.decade):
		return false
	if f.has("time") and not in_time(Library.playtime(g), str(f.time)):
		return false
	if f.has("ach"):
		var a: Array = ach.get(str(g.get("id", "")), [])
		if a.size() < 2 or int(a[1]) <= 0:
			return false
		if str(f.ach) == "offen" and int(a[0]) >= int(a[1]):
			return false
		if str(f.ach) == "komplett" and int(a[0]) < int(a[1]):
			return false
	if f.has("tag"):
		var tags := GameFields.tags_of(g)
		if str(f.tag) == "?":
			if not tags.is_empty():
				return false
		elif not Array(tags).any(func(t): return str(t).to_lower() == str(f.tag).to_lower()):
			return false
	if f.has("category"):
		var c := GameFields.category_of(g)
		if (c != "") if str(f.category) == "?" else (c.to_lower() != str(f.category).to_lower()):
			return false
	for k in ["age", "region"]:
		if f.has(k) and str(g.get(k, "")) != ("" if str(f[k]) == "?" else str(f[k])):
			return false
	if f.has("status") and not Backlog.status_matches(g, str(f.status)):
		return false
	if f.has("stars") and not Backlog.stars_match(g, str(f.stars)):
		return false
	return true


static func in_time(secs: int, range_id: String) -> bool:
	match range_id:
		"lt1": return secs < 3600
		"1-10": return secs >= 3600 and secs < 36000
		"10-50": return secs >= 36000 and secs < 180000
		"gt50": return secs >= 180000
	return true


## Woher ein Spiel kommt: der Laden (Steam, Epic, EA, PC) oder das System des Emulators.
static func platform_of(g: Dictionary) -> String:
	var src := str(g.get("source", ""))
	if src in ["steam", "epic", "ea", "pc"] or src in Stores.EXTRA:
		return src
	return str(g.get("system", ""))


## Alle Läden eines Spiels: sein eigener und die seiner Doppelten (dasselbe Spiel bei Steam und GOG
## steht als ein Eintrag da, findet sich aber unter beiden). Die IDs der Doppelten beginnen mit
## ihrer Quelle („gog:…“).
static func platforms_of(g: Dictionary) -> Array:
	var out: Array = [platform_of(g)]
	var alts: Variant = g.get("alts")
	if alts is Array:
		for a in alts:
			var s := str(a).get_slice(":", 0)
			if s in Stores.PRIORITY and not out.has(s):
				out.append(s)
	return out


static func platform_name(key: String) -> String:
	match key:
		"steam": return "Steam"
		"epic": return "Epic Games"
		"ea": return "EA app"
		"pc": return "PC-Spiele"
		"": return UNKNOWN
	if key in Stores.EXTRA:
		return Stores.name_of(key)
	var n := str(Config.system(key).get("name", ""))
	return n if n != "" else key.to_upper()


static func played(g: Dictionary) -> bool:
	return Library.playtime(g) > 0 or Library.last_played(g) > 0


static func genres_of(g: Dictionary) -> PackedStringArray:
	var v: Variant = g.get("genres")
	return PackedStringArray(v) if v is Array or v is PackedStringArray else PackedStringArray()


## Jahrzehnt der Erscheinung (2010 für 2014) oder -1 ohne Angabe.
static func decade_of(g: Dictionary) -> int:
	var y := int(g.get("year", 0))
	return y - y % 10 if y > 0 else -1


## Erscheinungsjahr aus der Angabe des Steam-Shops („25. Feb. 2022“, „Feb 25, 2022“, „Q1 2024“).
## 0, wenn keine Jahreszahl darin steht („Demnächst“).
static func year_of(release: String) -> int:
	var m := _re_year.search(release)
	return int(m.get_string(1)) if m else 0


# --- Abschnitte ------------------------------------------------------------------------------

## Abschnitte des Rasters: [{ title, games, unknown }] in der Reihenfolge, in der sie stehen. Die
## Spiele behalten darin die Sortierung der Liste. Ohne Gruppierung ein Abschnitt ohne Titel.
## Genre: das zuerst genannte (wie im Steam-Shop) – ein Spiel steht nur einmal im Raster; der
## Filter findet es unter jedem seiner Genres.
static func groups(list: Array, by: String) -> Array:
	match by:
		"platform", "genre", "decade", "year", "category", "age", "region", "status", "stars":
			pass
		"series":
			return _series_groups(list)
		"tag":
			return _tag_groups(list)
		_:
			return [{ "title": "", "games": list, "unknown": false }]
	var buckets := {}
	var keys: Array = []
	for g in list:
		var k: Variant = group_key(g, by)
		if not buckets.has(k):
			buckets[k] = []
			keys.append(k)
		(buckets[k] as Array).append(g)
	var out: Array = []
	for k in keys:
		var unknown: bool = (k is int and k < 0) or (k is String and k == "")
		var none := { "category": NO_CATEGORY, "status": Backlog.NO_STATUS, "stars": Backlog.NO_STARS }.get(by, UNKNOWN) as String
		out.append({ "title": none if unknown else group_title(k, by), "games": buckets[k], "unknown": unknown, "key": k })
	out.sort_custom(_before_status if by == "status" else _before)
	for e in out:
		e.erase("key")
	return out


static func group_key(g: Dictionary, by: String) -> Variant:
	match by:
		"platform":
			return platform_of(g)
		"genre":
			var gen := genres_of(g)
			return gen[0] if not gen.is_empty() else ""
		"decade":
			return decade_of(g)
		"year":
			var y := int(g.get("year", 0))
			return y if y > 0 else -1
		"category":
			return GameFields.category_of(g)
		"age":
			return str(g.get("age", "")) if GameFields.age_label(str(g.get("age", ""))) != "" else ""
		"region":
			return str(g.get("region", "")) if GameFields.region_label(str(g.get("region", ""))) != "" else ""
		"status":
			return Backlog.status_of(g)
		"stars":
			var h := Backlog.stars_of(g)
			return h if h > 0 else -1
	return ""


static func group_title(k: Variant, by: String) -> String:
	match by:
		"platform": return platform_name(str(k))
		"decade": return "%der" % int(k)
		"age": return GameFields.age_label(str(k))
		"region": return GameFields.region_label(str(k))
		"status": return Backlog.status_name(str(k))
		"stars": return Backlog.stars_text(int(k))
	return str(k)


## Unbekanntes ans Ende, Jahre und Sterne absteigend (Neues bzw. Bestes zuerst), sonst nach dem
## Alphabet.
static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a.unknown != b.unknown:
		return b.unknown
	if a.key is int and b.key is int:
		return int(a.key) > int(b.key)
	return str(a.title).naturalnocasecmp_to(str(b.title)) < 0


## Backlog-Status in der Reihenfolge von Backlog.STATUSES („Spiele ich“ zuerst), ohne Status am Ende.
static func _before_status(a: Dictionary, b: Dictionary) -> bool:
	if a.unknown != b.unknown:
		return b.unknown
	return _status_rank(str(a.key)) < _status_rank(str(b.key))


static func _status_rank(k: String) -> int:
	for i in Backlog.STATUSES.size():
		if Backlog.STATUSES[i][0] == k:
			return i
	return Backlog.STATUSES.size()


## Reihen nur, wenn sie eindeutig sind: mindestens zwei verschiedene Titel mit demselben Namen
## vorn (siehe series_of). Alles andere steht am Ende unter „Einzelne Spiele“.
static func _series_groups(list: Array) -> Array:
	var keys: Array = []
	var names := {}        # Reihe (klein) → { Titel (klein): true }
	var shown := {}        # Reihe (klein) → Name, wie er beim ersten Spiel geschrieben ist
	for g in list:
		var t := Library.display_title(g)
		var s := series_of(t)
		var k := s.to_lower()
		keys.append(k)
		if not names.has(k):
			names[k] = {}
			shown[k] = s
		(names[k] as Dictionary)[t.to_lower()] = true
	var buckets := {}
	var rest: Array = []
	for i in list.size():
		var k: String = keys[i]
		if (names[k] as Dictionary).size() < 2:
			rest.append(list[i])
			continue
		if not buckets.has(k):
			buckets[k] = []
		(buckets[k] as Array).append(list[i])
	var out: Array = []
	for k in buckets:
		out.append({ "title": shown[k], "games": buckets[k], "unknown": false })
	out.sort_custom(func(a, b): return str(a.title).naturalnocasecmp_to(str(b.title)) < 0)
	if not rest.is_empty():
		out.append({ "title": NO_SERIES, "games": rest, "unknown": true })
	return out


## Nach Tag: Ein Spiel steht unter jedem seiner Tags (wie ein Regal je Tag), Spiele ohne Tag am
## Ende unter „Ohne Tag“. Tags in anderer Groß-/Kleinschreibung zählen als derselbe.
static func _tag_groups(list: Array) -> Array:
	var buckets := {}
	var shown := {}
	var rest: Array = []
	for g in list:
		var tags := GameFields.tags_of(g)
		if tags.is_empty():
			rest.append(g)
			continue
		var seen := {}
		for t in tags:
			var k := t.to_lower()
			if seen.has(k):
				continue
			seen[k] = true
			if not buckets.has(k):
				buckets[k] = []
				shown[k] = t
			(buckets[k] as Array).append(g)
	var out: Array = []
	for k in buckets:
		out.append({ "title": shown[k], "games": buckets[k], "unknown": false })
	out.sort_custom(func(a, b): return str(a.title).naturalnocasecmp_to(str(b.title)) < 0)
	if not rest.is_empty():
		out.append({ "title": NO_TAG, "games": rest, "unknown": true })
	return out


## Name der Reihe aus dem Titel, vorsichtig: der Teil vor einem Untertitel („The Legend of Zelda:
## The Wind Waker“), ohne Nummer am Ende („Final Fantasy VII“, „Tekken 3“, „FIFA 23“) und ohne
## Zusätze wie „Remastered“ oder „Definitive Edition“. Bleibt weniger als drei Zeichen übrig, zählt
## der ganze Titel. Ob daraus wirklich eine Reihe wird, entscheidet erst _series_groups.
static func series_of(title: String) -> String:
	if _series.has(title):
		return _series[title]
	var t := title.strip_edges()
	var cut := t.length()
	for sep in [":", " - ", " – ", " — "]:
		var i := t.find(sep)
		if i > 0 and i < cut:
			cut = i
	t = t.left(cut).strip_edges()
	var before := ""
	while before != t:
		before = t
		var e := _re_edition.search(t)
		if e and e.get_start() >= 3:
			t = t.left(e.get_start()).strip_edges()
		var m := _re_tail.search(t)
		if m and m.get_start() >= 3:
			t = t.left(m.get_start()).strip_edges()
	if t.length() < 3:
		t = title.strip_edges()
	if _series.size() > _CACHE_MAX:
		_series.clear()
	_series[title] = t
	return t


# --- Auswahl und Text ------------------------------------------------------------------------

## Was die Spiele für die Auswahl hergeben, mit Anzahl: { platform: { key: n }, genre: { name: n },
## decade: { 2010: n }, no_genre, no_year, installed, missing (nicht installiert) }.
static func facets(list: Array) -> Dictionary:
	var plat := {}
	var gen := {}
	var dec := {}
	var no_genre := 0
	var no_year := 0
	var inst := 0
	for g in list:
		for p in platforms_of(g):
			plat[p] = int(plat.get(p, 0)) + 1
		var gs := genres_of(g)
		if gs.is_empty():
			no_genre += 1
		for x in gs:
			gen[x] = int(gen.get(x, 0)) + 1
		var d := decade_of(g)
		if d < 0:
			no_year += 1
		else:
			dec[d] = int(dec.get(d, 0)) + 1
		if Library.is_installed(g):
			inst += 1
	var ages := {}
	var regions := {}
	for g in list:
		for k in [["age", ages], ["region", regions]]:
			var v := str(g.get(k[0], ""))
			if v != "":
				k[1][v] = int(k[1].get(v, 0)) + 1
	var tags := GameFields.all_tags(list)
	var cats := GameFields.categories(list)
	var status := {}
	var stars := {}
	for g in list:
		var st := Backlog.status_of(g)
		if st != "":
			status[st] = int(status.get(st, 0)) + 1
		for e in Backlog.STAR_FILTERS:
			if Backlog.stars_of(g) > 0 and Backlog.stars_match(g, str(e[0])):
				stars[e[0]] = int(stars.get(e[0], 0)) + 1
	return { "platform": plat, "genre": gen, "decade": dec, "no_genre": no_genre, "no_year": no_year,
		"installed": inst, "missing": list.size() - inst, "tag": tags, "category": cats, "age": ages, "region": regions,
		"no_tag": list.filter(func(g): return GameFields.tags_of(g).is_empty()).size(),
		"no_category": list.filter(func(g): return GameFields.category_of(g) == "").size(),
		"status": status, "stars": stars }


## Kurz, was der Filter zeigt („Installiert · PlayStation 2 · Action“), für den Kopf des Rasters.
static func summary(f: Dictionary) -> String:
	var bits := PackedStringArray()
	if f.has("platform"):
		bits.append(platform_name(str(f.platform)))
	if f.has("installed"):
		bits.append("Installiert" if f.installed == "ja" else "Nicht installiert")
	if f.has("played"):
		bits.append("Gespielt" if f.played == "ja" else "Nie gespielt")
	if f.get("fav", false):
		bits.append("Favoriten")
	if f.has("genre"):
		bits.append("Genre unbekannt" if f.genre == "?" else str(f.genre))
	if f.has("decade"):
		bits.append("Jahr unbekannt" if int(f.decade) < 0 else "%der" % int(f.decade))
	if f.has("time"):
		bits.append(_label(TIMES, str(f.time)))
	if f.has("ach"):
		bits.append(_label(ACH, str(f.ach)))
	if f.has("tag"):
		bits.append(NO_TAG if f.tag == "?" else "Tag: %s" % f.tag)
	if f.has("category"):
		bits.append(NO_CATEGORY if f.category == "?" else "Kategorie: %s" % f.category)
	if f.has("age"):
		bits.append("Altersfreigabe unbekannt" if f.age == "?" else GameFields.age_label(str(f.age)))
	if f.has("region"):
		bits.append("Region unbekannt" if f.region == "?" else GameFields.region_label(str(f.region)))
	if f.has("status"):
		bits.append(Backlog.NO_STATUS if f.status == "?" else Backlog.status_name(str(f.status)))
	if f.has("stars"):
		bits.append(Backlog.star_filter_name(str(f.stars)))
	return " · ".join(bits)


static func group_name(by: String) -> String:
	return _label(GROUPS, by)


static func _label(list: Array, key: String) -> String:
	for e in list:
		if e[0] == key:
			return str(e[1])
	return ""


# --- Gespeichertes prüfen --------------------------------------------------------------------

## Filter aus den Einstellungen: nur bekannte Felder mit passendem Wert (die Datei kann von Hand
## geändert oder von einer anderen Version sein).
static func clean(v: Variant) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	var f: Dictionary = v
	for k in ["platform", "genre", "tag", "category"]:
		if f.get(k) is String and str(f[k]) != "":
			out[k] = str(f[k]).left(80)
	if f.get("age") is String and (f.age == "?" or GameFields.age_label(f.age) != ""):
		out["age"] = str(f.age)
	if f.get("region") is String and (f.region == "?" or GameFields.region_label(f.region) != ""):
		out["region"] = str(f.region)
	if f.get("status") is String and (f.status == "?" or Backlog.status_name(f.status) != ""):
		out["status"] = str(f.status)
	if f.get("stars") is String and Backlog.star_filter_name(f.stars) != "":
		out["stars"] = str(f.stars)
	for k in ["installed", "played"]:
		if f.get(k) is String and str(f[k]) in ["ja", "nein"]:
			out[k] = str(f[k])
	if f.get("fav") is bool and f.fav:
		out["fav"] = true
	if f.get("decade") is int or f.get("decade") is float:
		var d := int(f.decade)
		if d == -1 or (d >= 1950 and d <= 2090 and d % 10 == 0):
			out["decade"] = d
	if f.get("time") is String and _label(TIMES, str(f.time)) != "":
		out["time"] = str(f.time)
	if f.get("ach") is String and _label(ACH, str(f.ach)) != "":
		out["ach"] = str(f.ach)
	return out


static func clean_group(v: Variant) -> String:
	return str(v) if v is String and _label(GROUPS, str(v)) != "" else ""


## Gespeicherte Ansichten: [{ name, filter, group, sort }], höchstens PRESETS_MAX, Namen eindeutig.
static func clean_presets(v: Variant, sorts: Array) -> Array:
	var out: Array = []
	if not (v is Array):
		return out
	var seen := {}
	for p in v:
		if not (p is Dictionary):
			continue
		var n := str(p.get("name", "")).strip_edges().left(NAME_MAX)
		if n == "" or seen.has(n.to_lower()):
			continue
		seen[n.to_lower()] = true
		var s := str(p.get("sort", ""))
		out.append({ "name": n, "filter": clean(p.get("filter")), "group": clean_group(p.get("group")),
			"sort": s if _label(sorts, s) != "" else "" })
		if out.size() >= PRESETS_MAX:
			break
	return out

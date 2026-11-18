extends RefCounted
## Reihe „Retro-Klassiker“ im Shop (Roadmap 130): offizielle Sammlungen und Neuauflagen klassischer
## Spiele im Steam-Shop, gefunden über die vorhandene Shop-Suche (Store.load_retro_classics).
## Rechnet nur: keine Knoten, kein Netz, getestet in tests/logic_spielmenus.gd. Uzai nennt nie
## Quellen für ROMs, BIOS oder Firmware und verlinkt nichts dergleichen (R5).

const RetroMatch := preload("res://src/core/retro_match.gd")

## Zusätze, die ein Remaster oder eine Neuauflage im Namen tragen darf, ohne ein anderes Spiel zu sein
## („Okami“ → „Okami HD“, „Persona 4“ → „Persona 4 Golden“). Zahlen gehören nie dazu (Fortsetzungen).
const AUFLAGE := ["hd", "remaster", "remastered", "remake", "definitive", "edition", "collection", "classic", "classics",
	"deluxe", "anniversary", "reignited", "trilogy", "dx", "redux", "complete", "directors", "cut", "golden", "royal",
	"portable", "zodiac", "age", "ultimate", "special", "enhanced", "legacy", "master", "version", "the", "of", "pixel",
	"reloaded", "returns", "plus", "integral", "goty", "game", "year", "digital", "steam", "pc", "and", "for", "windows"]

## Was bei Shop-Treffern kein Spiel ist.
const KEIN_SPIEL := ["soundtrack", " ost", "ost ", "artbook", "art book", "wallpaper", "season pass", "upgrade", "costume",
	"demo", "playtest", "dedicated server", "sdk", "editor", "dlc", "expansion pass", "bonus content"]

## Offizielle Sammlungen klassischer Spiele im Steam-Shop für die Reihe „Retro-Klassiker“: das
## Suchwort (so heißt das Angebot). Nur Namen – keine Bilder, keine Adressen außer der Shop-Suche.
const SAMMLUNGEN := [
	{ "suche": "SEGA Mega Drive and Genesis Classics" },
	{ "suche": "Sonic Origins" },
	{ "suche": "Mega Man Legacy Collection" },
	{ "suche": "Mega Man X Legacy Collection" },
	{ "suche": "Castlevania Anniversary Collection" },
	{ "suche": "Castlevania Advance Collection" },
	{ "suche": "Street Fighter 30th Anniversary Collection" },
	{ "suche": "Capcom Arcade Stadium" },
	{ "suche": "Teenage Mutant Ninja Turtles: The Cowabunga Collection" },
	{ "suche": "Atari 50: The Anniversary Celebration" },
	{ "suche": "Klonoa Phantasy Reverie Series" },
	{ "suche": "Crash Bandicoot N. Sane Trilogy" },
	{ "suche": "Spyro Reignited Trilogy" },
	{ "suche": "Tomb Raider I-III Remastered" },
	{ "suche": "METAL GEAR SOLID: MASTER COLLECTION Vol. 1" },
	{ "suche": "Shenmue I & II" },
	{ "suche": "KINGDOM HEARTS -HD 1.5+2.5 ReMIX-" },
	{ "suche": "FINAL FANTASY X/X-2 HD Remaster" },
	{ "suche": "Okami HD" },
]


## Vergleichbare Wörter (klein, ohne Klammern und Satzzeichen).
static func tokens(s: String) -> PackedStringArray:
	return RetroMatch.norm(s).split(" ", false)


## Ist der Shop-Name dasselbe Spiel bzw. dasselbe Angebot wie wanted? Gleich, oder alle Wörter von
## wanted kommen vor und der Rest sind nur Zusätze einer Neuauflage (AUFLAGE). Fortsetzungen
## („Mega Man“ ≠ „Mega Man 11“) und andere Spiele („Resident Evil Village“) fallen so heraus.
## loose (Sammlungen, deren Name im Shop noch einen Zusatz trägt: „Tomb Raider I-III Remastered
## Starring Lara Croft“): jeder Zusatz außer Zahlen ist erlaubt.
static func legal_match(wanted: String, name: String, loose := false) -> bool:
	var a := tokens(wanted)
	var b := tokens(name)
	if a.is_empty() or b.is_empty():
		return false
	if a == b:
		return true
	for t in a:
		if not (t in b):
			return false
	for t in b:
		if t in a:
			continue
		if is_number_word(t) or not (loose or t in AUFLAGE):
			return false
	return true


## Zahl oder römische Zahl („2“, „iii“) – Kennzeichen einer Fortsetzung.
static func is_number_word(t: String) -> bool:
	return t.is_valid_int() or t in ["ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii", "xiii", "xiv", "xv", "xvi"]


## Kein Spiel (Soundtrack, Artbook, Erweiterung …)?
static func not_a_game(name: String) -> bool:
	var low := " " + name.to_lower() + " "
	return KEIN_SPIEL.any(func(w: String) -> bool: return low.contains(w))


## Die Sammlungen für die Reihe „Retro-Klassiker“ im Shop.
static func shop_collections() -> Array:
	return SAMMLUNGEN


## Passende Treffer aus einer Shop-Suche (Einträge wie Store.parse_search_item): nur Spiele, deren
## Name zu wanted passt, die genaueste zuerst. limit: so viele höchstens; loose wie legal_match.
static func pick(items: Array, wanted: String, limit := 2, loose := false) -> Array:
	var scored: Array = []
	for it in items:
		if not (it is Dictionary) or int(it.get("appid", 0)) <= 0:
			continue
		var name := str(it.get("name", ""))
		if name == "" or not_a_game(name) or not legal_match(wanted, name, loose):
			continue
		var extra := tokens(name).size() - tokens(wanted).size()
		scored.append([extra, it])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var out: Array = []
	for s in scored.slice(0, limit):
		out.append(s[1])
	return out


## Treffer aus mehreren Suchen zusammenlegen (jedes Angebot nur einmal, Reihenfolge bleibt).
static func merge_unique(lists: Array, limit := 8) -> Array:
	var seen := {}
	var out: Array = []
	for l in lists:
		for it in (l if l is Array else []):
			var id := int((it as Dictionary).get("appid", 0))
			if id <= 0 or seen.has(id):
				continue
			seen[id] = true
			out.append(it)
			if out.size() >= limit:
				return out
	return out


## Cache-Eintrag aus der Platte prüfen: nur Einträge mit Zahl und Namen, nur bekannte Felder
## (fremde Datei – nichts ungeprüft übernehmen).
static func clean_cached(raw: Variant) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for it in raw:
		if not (it is Dictionary):
			continue
		var id := int(it.get("appid", 0)) if (it.get("appid") is int or it.get("appid") is float) else 0
		var name := str(it.get("name", "")) if it.get("name") is String else ""
		if id <= 0 or id > 100000000 or name == "" or name.length() > 200:
			continue
		out.append({ "appid": id, "name": name })
		if out.size() >= 20:
			break
	return out

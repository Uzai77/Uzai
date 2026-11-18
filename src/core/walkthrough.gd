extends RefCounted
## Lösungshilfe (Punkt 111): YouTube-Videos zum laufenden Spiel – Komplettlösung, Bosse,
## Sammelobjekte … oder ein eigenes Suchwort („Boss Malenia“). Gesucht wird nur über Uzais
## YouTube-Suche (yt-dlp), gespielt im vorhandenen Bild in Bild über dem Spiel (src/core/pip.gd).
## Hier die Regeln ohne Oberfläche: Suchbegriff je Spiel und Sprache, gemerkte Suchwörter je Spiel
## (lokal in youtube.json, Feld „help“). Oberfläche: src/ui/layers/walkthrough_sheet.gd.

## Themen: [Kennung, Name, Symbol, Zusatz Deutsch, Zusatz Englisch].
const TOPICS := [
	["komplett", "Komplettlösung", "list", "Komplettlösung deutsch", "full walkthrough"],
	["bosse", "Bosse", "bolt", "alle Bosse Guide deutsch", "all bosses guide"],
	["sammeln", "Sammelobjekte", "star", "alle Sammelobjekte Fundorte deutsch", "all collectibles locations"],
	["erfolge", "Erfolge und Trophäen", "trophy", "Erfolge Trophäen Guide deutsch", "achievement trophy guide"],
	["tipps", "Tipps für den Anfang", "info", "Tipps Tricks Anfänger deutsch", "beginner tips and tricks"],
]
const TERMS_MAX := 6           ## gemerkte Suchwörter je Spiel
const GAMES_MAX := 60          ## so viele Spiele merkt sich Uzai, die ältesten fallen raus
const TERM_MAX := 60           ## Zeichen je Suchwort
const TITLE_MAX := 80
const RESULTS_MAX := 20
## Wörter, an denen man sieht, dass schon nach einer Lösung gefragt ist (dann nichts anhängen).
const HELP_WORDS := ["guide", "lösung", "loesung", "walkthrough", "tipps", "tips", "tutorial", "how to", "fundort"]
const GERMAN_WORDS := ["deutsch", "german"]


## Spielname für die Suche: ohne ™ ® ©, ohne Klammern aus Dateinamen („(Europe)“, „[!]“), ohne
## doppelte Leerzeichen, nicht endlos lang.
static func clean_title(t: String) -> String:
	var s := t
	for ch in ["™", "®", "©"]:
		s = s.replace(ch, "")
	var rx := RegEx.create_from_string("\\s*[\\(\\[][^\\)\\]]*[\\)\\]]")
	s = rx.sub(s, "", true)
	return _squeeze(s).left(TITLE_MAX).strip_edges()


## Eigenes Suchwort: ohne Steuerzeichen, Leerzeichen zusammengezogen, höchstens TERM_MAX Zeichen.
static func clean_term(t: String) -> String:
	var s := ""
	for ch in t:
		s += " " if ch.unicode_at(0) < 32 or ch.unicode_at(0) == 127 else ch
	return _squeeze(s).left(TERM_MAX).strip_edges()


static func _squeeze(s: String) -> String:
	var out := PackedStringArray()
	for w in s.split(" ", false):
		if w.strip_edges() != "":
			out.append(w.strip_edges())
	return " ".join(out)


## Sprache der Suche: Uzais Sprache, Deutsch oder sonst Englisch.
static func lang_now() -> String:
	return "de" if TranslationServer.get_locale().left(2) == "de" else "en"


## Suchbegriff für YouTube: Spielname plus Thema (TOPICS) oder eigenes Suchwort. Deutsch hängt
## „deutsch“ an (sonst kommen fast nur englische Videos), ein Suchwort ohne Hinweis auf eine Lösung
## bekommt „Guide“. "" ohne Spielnamen.
static func query(title: String, topic: String, term: String, lang: String) -> String:
	var base := clean_title(title)
	if base == "":
		return ""
	var t := clean_term(term)
	var extra := ""
	if t != "":
		var low := t.to_lower()
		extra = t
		if not HELP_WORDS.any(func(w: String) -> bool: return low.contains(w)):
			extra += " Guide" if lang == "de" else " guide"
		if lang == "de" and not GERMAN_WORDS.any(func(w: String) -> bool: return low.contains(w)):
			extra += " deutsch"
	else:
		var tp := topic_of(topic)
		extra = str(tp[3] if lang == "de" else tp[4])
	return ("%s %s" % [base, extra]).left(160)


## Thema nach Kennung, unbekannt: Komplettlösung.
static func topic_of(id: String) -> Array:
	for tp in TOPICS:
		if tp[0] == id:
			return tp
	return TOPICS[0]


## Treffer für die Liste: nur echte Videos (keine Shorts, keine Livestreams), jedes nur einmal,
## höchstens RESULTS_MAX.
static func pick(found: Array) -> Array:
	var out: Array = []
	var seen := {}
	for v in found:
		if not (v is Dictionary):
			continue
		var id := str(v.get("id", ""))
		if id == "" or seen.has(id) or bool(v.get("short", false)) or bool(v.get("live", false)):
			continue
		seen[id] = true
		var e: Dictionary = (v as Dictionary).duplicate()
		e["help"] = true             # aus der Lösungshilfe (Guide → Bild in Bild: „Andere Videos“)
		out.append(e)
		if out.size() >= RESULTS_MAX:
			break
	return out


## Zweite Zeile eines Treffers: „Kanal · 12:34“ bzw. „Kanal · 1:02:10“.
static func line_of(v: Dictionary) -> String:
	var bits := PackedStringArray()
	if str(v.get("channel", "")) != "":
		bits.append(str(v.channel))
	var d := int(v.get("duration", 0))
	if d > 0:
		bits.append(clock(d))
	return "  ·  ".join(bits)


static func clock(sec: int) -> String:
	if sec >= 3600:
		return "%d:%02d:%02d" % [floori(sec / 3600.0), floori(sec / 60.0) % 60, sec % 60]
	return "%d:%02d" % [floori(sec / 60.0), sec % 60]


# --- Gemerkte Suchwörter (Einträge { game, terms, at }, neueste zuerst) ------------------------

## Suchwörter eines Spiels, neueste zuerst. Kaputtes (von Hand geändert) fällt weg.
static func terms_of(entries: Variant, game_id: String) -> Array:
	if not (entries is Array) or game_id == "":
		return []
	for e in entries:
		if e is Dictionary and str(e.get("game", "")) == game_id and e.get("terms") is Array:
			var out: Array = []
			for t in e.terms:
				var c := clean_term(str(t)) if t is String else ""
				if c != "" and not _has_term(out, c) and out.size() < TERMS_MAX:
					out.append(c)
			return out
	return []


## Suchwort merken: vorn (auch wenn es schon da war), höchstens TERMS_MAX je Spiel und GAMES_MAX
## Spiele. Gibt die neue Liste zurück, die alte bleibt unberührt.
static func remember(entries: Variant, game_id: String, term: String, now: int) -> Array:
	var t := clean_term(term)
	var list: Array = (entries as Array).duplicate(true) if entries is Array else []
	if t == "" or game_id == "":
		return list
	var terms := terms_of(list, game_id)
	for i in range(terms.size() - 1, -1, -1):
		if str(terms[i]).to_lower() == t.to_lower():
			terms.remove_at(i)
	terms.push_front(t)
	list = list.filter(func(e: Variant) -> bool: return e is Dictionary and str(e.get("game", "")) != game_id)
	list.push_front({ "game": game_id, "terms": terms.slice(0, TERMS_MAX), "at": now })
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("at", 0)) > int(b.get("at", 0)))
	return list.slice(0, GAMES_MAX)


## Suchwort vergessen (Y in der Liste). Ohne Wörter fällt das Spiel ganz weg.
static func forget(entries: Variant, game_id: String, term: String) -> Array:
	var list: Array = (entries as Array).duplicate(true) if entries is Array else []
	var out: Array = []
	for e in list:
		if not (e is Dictionary):
			continue
		if str(e.get("game", "")) == game_id:
			var rest := terms_of([e], game_id).filter(func(x: String) -> bool: return x.to_lower() != term.to_lower())
			if rest.is_empty():
				continue
			e["terms"] = rest
		out.append(e)
	return out


static func _has_term(list: Array, t: String) -> bool:
	return list.any(func(x: String) -> bool: return x.to_lower() == t.to_lower())


# --- Mit Uzai ------------------------------------------------------------------------------------

## Gibt es die Lösungshilfe gerade? Im Spiel, mit YouTube-Werkzeugen (oder in der Vorführung).
static func available() -> bool:
	return Launcher.in_game and (YouTube.demo or YouTube.tools_ready())


static func remembered(game_id: String) -> Array:
	return terms_of(YouTube.data.get("help", []), game_id)


static func keep(game_id: String, term: String) -> void:
	YouTube.data["help"] = remember(YouTube.data.get("help", []), game_id, term, int(Time.get_unix_time_from_system()))
	YouTube.save()


static func drop(game_id: String, term: String) -> void:
	YouTube.data["help"] = forget(YouTube.data.get("help", []), game_id, term)
	YouTube.save()


## Suchen (yt-dlp über YouTube.search, ohne die Videos-Suche mit diesen Begriffen zu füllen).
## In der Vorführung: Beispieltreffer aus tests/demo_youtube.json („help_videos“).
static func search(title: String, topic: String, term: String) -> Array:
	var q := query(title, topic, term, lang_now())
	if q == "":
		return []
	if YouTube.demo:
		await (Engine.get_main_loop() as SceneTree).create_timer(0.6).timeout
		var words := term if term != "" else str(topic_of(topic)[1])
		return pick(demo_results(Config.read_json("res://tests/demo_youtube.json", {}), title, words))
	return pick(await YouTube.search(q, false))


## Vorführung: Treffer zum Spiel (Feld „game“ im Namen enthalten); was Wörter des Suchworts bzw.
## Themas (ab vier Buchstaben) im Titel hat, zuerst.
static func demo_results(d: Variant, title: String, term: String) -> Array:
	if not (d is Dictionary) or not (d.get("help_videos") is Array):
		return []
	var low := clean_title(title).to_lower()
	var mine: Array = (d.help_videos as Array).filter(func(v: Variant) -> bool:
		return v is Dictionary and str(v.get("game", "")) != "" and low.contains(str(v.game).to_lower()))
	var words := Array(clean_term(term).to_lower().split(" ", false)).filter(func(w: String) -> bool: return w.length() >= 4)
	if words.is_empty():
		return mine
	var hit := mine.filter(func(v: Dictionary) -> bool: return words.any(func(w: String) -> bool: return str(v.title).to_lower().contains(w)))
	return hit + mine.filter(func(v: Dictionary) -> bool: return not hit.has(v))

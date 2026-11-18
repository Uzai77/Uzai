extends RefCounted
## Was ein Discord-Freund gerade tut – nur aus dem, was Discord Uzai offiziell gibt:
## - Social SDK (UserHandle::GameActivity): laut Discord nur die Aktivität der eigenen App, also
##   bei Freunden, die Uzai mit derselben Discord-App nutzen. Uzais Status trägt den Spieltitel in
##   „details“ und Laden bzw. System mit „· Uzai“ in „state“ (game_presence.gd), Musik als Typ 2
##   (music_presence.gd); dazu seit wann.
## - der Zustand „Streamt“ (StatusType Streaming).
## - Server-Widgets (Social.discord): der Name der Aktivität von Leuten aus deinen Servern.
## Über-mich-Text, Banner und Aktivitäten anderer Apps gibt Discord an Apps nicht heraus – was
## fehlt, bleibt weg (keine leeren Zeilen). Reine Funktionen (tests/logic_discord_freunde.gd).

const People := preload("res://src/ui/components/guide_people.gd")

const TYPE_LISTENING := 2


## Rohe Angaben des Helfers (UserJson: game, details, activity_state, type, start, app) in Uzais
## Form: game (Titel), details (Zusatz wie „PlayStation 2“), music/artist, since (Unix-Sekunden).
## own_app: Uzais Discord-App-ID ("" = unbekannt).
static func normalize(raw: Dictionary, own_app := "") -> Dictionary:
	var name := _clean(raw.get("game", ""))
	var details := _clean(raw.get("details", ""))
	var st := _clean(raw.get("activity_state", ""))
	var sv: Variant = raw.get("start", 0)
	var start := int(sv) if (sv is int or sv is float) else 0
	# Das SDK meldet Millisekunden; Uzais eigener Status Sekunden.
	if start > 100000000000:
		start = int(start / 1000.0)
	var out := { "game": name, "details": details, "activity_state": st, "music": "", "artist": "", "since": maxi(start, 0) }
	if name == "" and details == "":
		out["since"] = 0
		return out
	if int(raw.get("type", 0)) == TYPE_LISTENING:
		out["game"] = ""
		out["details"] = ""
		out["activity_state"] = ""
		out["music"] = details if details != "" else name
		# Uzais Musik-Status schreibt „von <Künstler>“, im Englischen „by <Künstler>“ (music_presence.gd).
		out["artist"] = st.trim_prefix("von ").trim_prefix("by ").strip_edges()
		return out
	var app := str(raw.get("app", ""))
	var uzai := st == "Uzai" or st.ends_with(" · Uzai") or (own_app != "" and app == own_app)
	if uzai and details != "":
		# Uzais Status: „Ratchet & Clank“ / „PlayStation 2 · Uzai“ – der Titel ist das Spiel.
		out["game"] = details
		out["details"] = st.trim_suffix("Uzai").trim_suffix(" · ").strip_edges()
		out["activity_state"] = ""
	return out


## Was die Person gerade tut: { kind: "game" | "music" | "stream" | "", title, sub, since }.
## f: Discord-Freund (DiscordChat.friends); widget_game: Aktivität aus einem Server-Widget.
static func of(f: Dictionary, widget_game := "") -> Dictionary:
	var game := str(f.get("game", ""))
	var music := str(f.get("music", ""))
	if game != "":
		var bits := PackedStringArray()
		for k in ["details", "activity_state"]:
			if str(f.get(k, "")) != "":
				bits.append(str(f[k]))
		return { "kind": "game", "title": game, "sub": "  ·  ".join(bits), "since": int(f.get("since", 0)) }
	if music != "":
		return { "kind": "music", "title": music, "sub": str(f.get("artist", "")), "since": int(f.get("since", 0)) }
	if widget_game != "":
		return { "kind": "game", "title": widget_game, "sub": "", "since": 0 }
	if bool(f.get("streaming", false)):
		return { "kind": "stream", "title": "", "sub": "", "since": 0 }
	return { "kind": "", "title": "", "sub": "", "since": 0 }


## Die Zeile unter dem Namen: „Spielt X“, „Hört X“, „Streamt“ – "" ohne Aktivität.
static func headline(a: Dictionary) -> String:
	match str(a.get("kind", "")):
		"game":
			return "Spielt " + str(a.title)
		"music":
			return "Hört " + str(a.title)
		"stream":
			return "Streamt"
	return ""


## Zusatz in einer Zeile: „PlayStation 2 · seit 25 Min.“ ("" wenn nichts bekannt).
static func subline(a: Dictionary, now: int) -> String:
	var bits := PackedStringArray()
	if str(a.get("sub", "")) != "":
		bits.append(str(a.sub))
	var s := since_text(int(a.get("since", 0)), now)
	if s != "":
		bits.append(s)
	return "  ·  ".join(bits)


## „seit 25 Min.“ – "" ohne Startzeit oder bei unsinnigen Zeiten (Zukunft, über zwei Tage).
static func since_text(since: int, now: int) -> String:
	var secs := now - since
	if since <= 0 or secs < 0 or secs > 2 * 86400:
		return ""
	return "seit %s" % People.dur(secs)


## Name der Aktivität aus den Server-Widgets (gleicher Anzeige- oder Nutzername), sonst "".
static func widget_game(f: Dictionary, servers: Dictionary) -> String:
	var k := People.name_key(str(f.get("name", "")))
	var k2 := People.name_key(str(f.get("username", "")))
	for sid in servers.keys():
		var srv: Dictionary = servers[sid] if servers[sid] is Dictionary else {}
		for m in srv.get("members", []):
			if not (m is Dictionary):
				continue
			var mk := People.name_key(str((m as Dictionary).get("name", "")))
			if mk != "" and (mk == k or mk == k2) and str(m.get("game", "")) != "":
				return _clean(m.game)
	return ""


## Server (aus den Widgets), in denen dieser Mensch auch ist – nach Anzeige- oder Nutzername.
static func shared_servers(f: Dictionary, servers: Dictionary) -> Array:
	var out: Array = []
	var k := People.name_key(str(f.get("name", "")))
	var k2 := People.name_key(str(f.get("username", "")))
	for sid in servers.keys():
		var srv: Dictionary = servers[sid] if servers[sid] is Dictionary else {}
		for m in srv.get("members", []):
			var mk := People.name_key(str((m as Dictionary).get("name", ""))) if m is Dictionary else ""
			if mk != "" and (mk == k or mk == k2):
				out.append(str(srv.get("name", "Server")))
				break
	return out


## Das Spiel in deiner Bibliothek, das so heißt (installiert), sonst {}.
static func owned(title: String, games: Array) -> Dictionary:
	var t := People.title_key(title)
	if t == "":
		return {}
	for g in games:
		if g is Dictionary and People.title_key(str(g.get("title", ""))) == t and bool(g.get("installed", true)):
			return g
	return {}


## Eine Zeile aus fremden Daten: ohne Steuerzeichen, höchstens 128 Zeichen (Discords Grenze).
static func _clean(v: Variant) -> String:
	var s := str(v) if (v is String or v is StringName) else ""
	var out := ""
	for ch in s:
		out += " " if ch < " " else ch
	out = out.strip_edges()
	return out.left(128)

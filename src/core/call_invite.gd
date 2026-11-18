extends RefCounted
## Alle aus dem aktuellen Discord-Call (Sprachkanal, Anruf oder Gruppenanruf) auf einmal zu
## Remote Play Together einladen.
##
## Discord verrät nicht, wer jemand bei Steam ist – keine Schnittstelle verbindet die beiden
## Konten. Deshalb ordnest du jede Person einmal einem Steam-Freund zu; Uzai schlägt dafür den
## passenden Namen vor (Groß/klein, Akzente, Trennzeichen egal, Tippfehler und Teilnamen zählen)
## und merkt sich die Wahl (Einstellungen → Konten → Discord → „Zuordnungen Discord ↔ Steam“).
## Eingeladen wird wie beim einzelnen „Zu Remote Play einladen“ über ISteamRemotePlay
## (RemotePlay.send_invites): du selbst nicht, wer schon in der Sitzung ist auch nicht.
## Alles hier außer load_map/save_map/send ist rein und in tests/logic_remoteplay.gd geprüft.

const RemotePlay := preload("res://src/core/remote_play.gd")
const Lang := preload("res://src/core/lang.gd")

const MAP_KEY := "accounts.discord_steam"
## Darunter ist ein Steam-Freund kein Vorschlag.
const MIN_SCORE := 0.5
## Ab hier (und klar vor dem zweitbesten) gilt ein Vorschlag schon als gewählt.
const SURE := 0.86
const SURE_GAP := 0.08
## Steam nennt für Remote Play Together bis zu vier Spieler: du und drei Gäste.
const STEAM_GUESTS := 3

const _FOLD := {
	"à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a", "ā": "a", "ă": "a", "ą": "a", "æ": "ae",
	"ç": "c", "ć": "c", "č": "c", "ď": "d", "đ": "d", "ð": "d",
	"è": "e", "é": "e", "ê": "e", "ë": "e", "ē": "e", "ė": "e", "ę": "e", "ě": "e",
	"ğ": "g", "ì": "i", "í": "i", "î": "i", "ï": "i", "ī": "i", "ı": "i", "ł": "l", "ľ": "l",
	"ñ": "n", "ń": "n", "ň": "n", "ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o", "ø": "o", "ō": "o", "ő": "o",
	"œ": "oe", "ř": "r", "ś": "s", "š": "s", "ş": "s", "ß": "ss", "ť": "t", "þ": "th",
	"ù": "u", "ú": "u", "û": "u", "ü": "u", "ū": "u", "ů": "u", "ű": "u", "ý": "y", "ÿ": "y",
	"ź": "z", "ż": "z", "ž": "z",
}


# --- Namen vergleichen ------------------------------------------------------------------------

## Rein: klein, ohne Akzente; alles außer Buchstaben und Ziffern wird zum Leerzeichen.
## „PixelPaul“ und „pixel_paul“ werden zu „pixel paul“, „Müller“ zu „muller“, „Kai99“ zu „kai 99“.
static func fold(s: String) -> String:
	var out := ""
	var prev := ""
	for ch in s:
		# Wortgrenzen: klein → groß (CamelCase) und Buchstabe ↔ Ziffer.
		if prev != "" and _is_lower(prev) and ch != ch.to_lower():
			out += " "
		elif prev != "" and ((_is_digit(prev) and _is_alpha(ch)) or (_is_alpha(prev) and _is_digit(ch))):
			out += " "
		prev = ch
		var c := ch.to_lower()
		if _FOLD.has(c):
			out += _FOLD[c]
		elif (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		else:
			out += " "
	return " ".join(out.split(" ", false))


static func _is_lower(ch: String) -> bool:
	return ch != ch.to_upper() and ch == ch.to_lower()


static func _is_digit(ch: String) -> bool:
	return ch >= "0" and ch <= "9"


static func _is_alpha(ch: String) -> bool:
	return ch.to_lower() != ch.to_upper() or _FOLD.has(ch.to_lower())


## Rein: die Wörter eines Namens (ohne reine Zahlen, die sagen über einen Menschen wenig).
static func tokens(s: String) -> PackedStringArray:
	return _woerter(fold(s))


static func _woerter(gefaltet: String) -> PackedStringArray:
	var out := PackedStringArray()
	for t in gefaltet.split(" ", false):
		if not t.is_valid_int() and not out.has(t):
			out.append(t)
	return out


## Rein: ein Name, einmal für den Vergleich vorbereitet – { c: ohne Zwischenräume (compact), t: Wörter (tokens) }.
## fold geht den Namen Zeichen für Zeichen durch; früher lief es je Vergleich zweier Namen bis zu achtmal, bei
## mehreren hundert Steam-Freunden stand die Leiste dafür über eine Sekunde.
static func bereit(name: String) -> Dictionary:
	var f := fold(name)
	return { "c": f.replace(" ", ""), "t": _woerter(f) }


## Rein: der Name ohne Zwischenräume (Ziffern bleiben: „kai99“).
static func compact(s: String) -> String:
	return fold(s).replace(" ", "")


static func levenshtein(a: String, b: String) -> int:
	if a == b:
		return 0
	if a.is_empty():
		return b.length()
	if b.is_empty():
		return a.length()
	# Eine Zeile der Tabelle genügt: links der neue Wert, oben der alte, schräg oben der gemerkte.
	var n := b.length()
	var zeile := PackedInt32Array()
	zeile.resize(n + 1)
	for j in n + 1:
		zeile[j] = j
	for i in a.length():
		var schraeg := zeile[0]
		zeile[0] = i + 1
		var ai := a.unicode_at(i)
		for j in n:
			var oben := zeile[j + 1]
			var cost := 0 if ai == b.unicode_at(j) else 1
			zeile[j + 1] = mini(mini(zeile[j] + 1, oben + 1), schraeg + cost)
			schraeg = oben
	return zeile[n]


## Rein: 1 = gleich, 0 = nichts gemeinsam.
static func ratio(a: String, b: String) -> float:
	var n := maxi(a.length(), b.length())
	if n == 0:
		return 0.0
	return 1.0 - float(levenshtein(a, b)) / float(n)


## Rein: Wie gut passen zwei Namen? 0 … 1.
## Ganz gleich (nach fold) 1; sonst das Beste aus: Ähnlichkeit des ganzen Namens, ein gleiches
## (oder fast gleiches) Wort („Mira“ ↔ „Mira Müller“), ein Name steckt im anderen („paul“ in
## „pixelpaul“).
static func name_score(a: String, b: String) -> float:
	return _score(bereit(a), bereit(b))


## Wie name_score, mit vorbereiteten Namen (bereit).
static func _score(pa: Dictionary, pb: Dictionary) -> float:
	var ca: String = pa.c
	var cb: String = pb.c
	if ca == "" or cb == "":
		return 0.0
	if ca == cb:
		return 1.0
	var wa: PackedStringArray = pa.t
	var wb: PackedStringArray = pb.t
	var best := ratio(ca, cb)
	for ta in wa:
		for tb in wb:
			if ta.length() < 3 or tb.length() < 3:
				continue
			var r := 1.0 if ta == tb else ratio(ta, tb)
			if r >= 0.75:
				best = maxf(best, r * 0.9)
	var short := ca if ca.length() <= cb.length() else cb
	var long := cb if short == ca else ca
	if short.length() >= 4 and long.contains(short):
		best = maxf(best, 0.6 + 0.3 * float(short.length()) / float(long.length()))
	# Ein Wort des einen steckt im anderen Namen („Paul Berger“ ↔ „pixelpaul“).
	for pair in [[wa, cb], [wb, ca]]:
		var whole := str(pair[1])
		for t in (pair[0] as PackedStringArray):
			if t.length() >= 4 and t != whole and whole.contains(t):
				best = maxf(best, 0.55 + 0.3 * float(t.length()) / float(whole.length()))
	return clampf(best, 0.0, 1.0)


## Rein: alle Namen einer Person im Call (Spitzname im Server, Anzeigename, Benutzername).
static func discord_names(m: Dictionary) -> Array:
	var out: Array = []
	for k in ["name", "global_name", "username"]:
		var n := str(m.get(k, "")).strip_edges()
		if n != "" and not out.has(n):
			out.append(n)
	return out


## Rein: Name und (falls öffentlich) Klarname eines Steam-Freundes.
static func steam_names(f: Dictionary) -> Array:
	var out: Array = []
	for k in ["name", "real"]:
		var n := str(f.get(k, "")).strip_edges()
		if n != "" and not out.has(n):
			out.append(n)
	return out


## Der beste Wert über alle Paare zweier Listen vorbereiteter Namen (alle Namen einer Person im Call gegen alle
## eines Steam-Freundes).
static func _bester(da: Array, sb: Array) -> float:
	var best := 0.0
	for a in da:
		for b in sb:
			best = maxf(best, _score(a, b))
	return best


## Rein: die besten Steam-Freunde für eine Person im Call: [{ id, name, avatar, state, score }],
## bester zuerst, nur ab MIN_SCORE. vor: Zwischenspeicher der vorbereiteten Namen je Steam-Freund – wer mehrere
## Personen nacheinander fragt (build_plan), gibt dasselbe Wörterbuch mit und bereitet jeden Freund nur einmal vor.
static func suggest(m: Dictionary, friends: Array, n := 3, vor: Variant = null) -> Array:
	var bereitet: Dictionary = vor if vor is Dictionary else {}
	var da: Array = discord_names(m).map(bereit)
	var out: Array = []
	for f in friends:
		if not (f is Dictionary) or str(f.get("id", "")) == "":
			continue
		var fid := str(f.id)
		if not bereitet.has(fid):
			bereitet[fid] = steam_names(f).map(bereit)
		var s := _bester(da, bereitet[fid])
		if s >= MIN_SCORE:
			out.append({ "id": str(f.id), "name": str(f.get("name", "")), "avatar": str(f.get("avatar", "")), "state": str(f.get("state", "")), "score": s })
	out.sort_custom(func(a, b):
		if absf(float(a.score) - float(b.score)) > 0.0001:
			return float(a.score) > float(b.score)
		# Gleich gut: wer online ist, zuerst.
		var ao := str(a.state) != "offline"
		var bo := str(b.state) != "offline"
		if ao != bo:
			return ao
		return str(a.name).naturalnocasecmp_to(str(b.name)) < 0
	)
	return out.slice(0, n)


## Rein: Ist der beste Vorschlag so klar, dass Uzai ihn ohne Nachfrage nimmt?
static func sure(sugg: Array) -> bool:
	if sugg.is_empty() or float(sugg[0].score) < SURE:
		return false
	return sugg.size() < 2 or float(sugg[0].score) - float(sugg[1].score) >= SURE_GAP


# --- Zuordnungen (Discord-ID → Steam-ID) --------------------------------------------------------

## Rein: Zuordnung setzen. map bleibt unverändert, zurück kommt die neue.
static func map_set(map: Dictionary, discord_id: String, steam_id: String, discord_name := "", steam_name := "", now := 0) -> Dictionary:
	var out := map.duplicate(true)
	if discord_id == "":
		return out
	if steam_id == "":
		out.erase(discord_id)
		return out
	out[discord_id] = { "steam": steam_id, "discord_name": discord_name, "steam_name": steam_name, "at": now }
	return out


static func map_remove(map: Dictionary, discord_id: String) -> Dictionary:
	var out := map.duplicate(true)
	out.erase(discord_id)
	return out


## Rein: Steam-ID zu einer Discord-ID ("" ohne Zuordnung).
static func map_steam(map: Dictionary, discord_id: String) -> String:
	var e: Variant = map.get(discord_id)
	if e is Dictionary:
		return str(e.get("steam", ""))
	if e is String:
		return e
	return ""


## Rein: nur gültige Einträge (von Hand geänderte Datei, ältere Fassung mit nur der Steam-ID).
static func clean_map(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for k in raw.keys():
		var e: Variant = raw[k]
		if e is String and str(e) != "":
			out[str(k)] = { "steam": str(e), "discord_name": "", "steam_name": "", "at": 0 }
		elif e is Dictionary and str(e.get("steam", "")) != "":
			out[str(k)] = { "steam": str(e.steam), "discord_name": str(e.get("discord_name", "")), "steam_name": str(e.get("steam_name", "")),
					"at": int(e.get("at", 0)) }
	return out


## Rein: für die Liste in den Einstellungen, nach Discord-Namen sortiert:
## [{ discord_id, discord_name, steam, steam_name }]. friends frischt den Steam-Namen auf.
static func map_rows(map: Dictionary, friends: Array) -> Array:
	var names := {}
	for f in friends:
		if f is Dictionary:
			names[str(f.get("id", ""))] = str(f.get("name", ""))
	var out: Array = []
	for k in map.keys():
		var e: Dictionary = map[k]
		var sn := str(names.get(str(e.steam), e.get("steam_name", "")))
		out.append({ "discord_id": str(k), "discord_name": str(e.get("discord_name", "")) if str(e.get("discord_name", "")) != "" else str(k),
			"steam": str(e.steam), "steam_name": sn if sn != "" else str(e.steam) })
	out.sort_custom(func(a, b): return str(a.discord_name).naturalnocasecmp_to(str(b.discord_name)) < 0)
	return out


static func load_map() -> Dictionary:
	return clean_map(Config.get_value(MAP_KEY, {}))


static func save_map(map: Dictionary) -> void:
	Config.set_value(MAP_KEY, clean_map(map))


static func remember(discord_id: String, steam_id: String, discord_name: String, steam_name: String) -> void:
	save_map(map_set(load_map(), discord_id, steam_id, discord_name, steam_name, int(Time.get_unix_time_from_system())))


static func forget(discord_id: String) -> void:
	save_map(map_remove(load_map(), discord_id))


# --- Wen einladen --------------------------------------------------------------------------------

## Rein: Wer aus dem Call wird eingeladen, und warum die anderen nicht?
## members: Voice.members · map: Zuordnungen · choice: Wahl in der Leiste für diesmal
## (Discord-ID → Steam-ID, "" = nicht einladen) · friends: Steam-Freunde (leer = unbekannt, dann
## prüft Uzai die Freundschaft nicht) · me_discord/me_steam: du selbst · joined: Steam-IDs schon in
## der Sitzung.
## rows (eine je Person, ohne dich und ohne Bots): { id, name, avatar, steam, steam_name, how, status,
## suggestions } mit how = map | choice | suggest | "" und status = invite | joined | unmapped |
## excluded | not_friend | duplicate.
## Dazu invite (die rows mit status invite), self (wie oft du selbst auftauchst) und guests (wie
## viele dann mitspielen: schon dabei + eingeladen).
static func build_plan(members: Array, map: Dictionary, choice: Dictionary, friends: Array, me_discord: String, me_steam: String, joined: Array) -> Dictionary:
	var by_id := {}
	for f in friends:
		if f is Dictionary:
			by_id[str(f.get("id", ""))] = f
	var rows: Array = []
	var invite: Array = []
	var seen := {}
	var self_n := 0
	var joined_n := 0
	var vor := {}        # vorbereitete Namen der Steam-Freunde, für alle Personen im Call gemeinsam
	for m in members:
		if not (m is Dictionary):
			continue
		var did := str(m.get("id", ""))
		if bool(m.get("me", false)) or (did != "" and did == me_discord):
			self_n += 1
			continue
		if bool(m.get("bot", false)):
			continue
		var row := { "id": did, "name": str(m.get("name", "?")), "avatar": str(m.get("avatar", "")), "steam": "", "steam_name": "",
			"how": "", "status": "unmapped", "suggestions": [] }
		var sid := ""
		if choice.has(did):
			sid = str(choice[did])
			row.how = "choice"
			if sid == "":
				row.status = "excluded"
		else:
			sid = map_steam(map, did)
			if sid != "":
				row.how = "map"
		if row.how == "":
			var sugg := suggest(m, friends, 3, vor)
			row.suggestions = sugg
			if sure(sugg):
				sid = str(sugg[0].id)
				row.how = "suggest"
		elif row.how == "map" and not friends.is_empty() and not by_id.has(sid):
			row.suggestions = suggest(m, friends, 3, vor)
		if sid != "":
			row.steam = sid
			var f: Dictionary = by_id.get(sid, {})
			var known: Dictionary = map.get(did) if map.get(did) is Dictionary else {}
			row.steam_name = str(f.get("name", "")) if not f.is_empty() else str(known.get("steam_name", ""))
			if row.how == "choice" or row.how == "suggest":
				for s in row.suggestions:
					if str(s.id) == sid and row.steam_name == "":
						row.steam_name = str(s.name)
			if sid == me_steam and me_steam != "":
				self_n += 1
				continue
			if joined.has(sid):
				row.status = "joined"
				joined_n += 1
			elif seen.has(sid):
				row.status = "duplicate"
			elif not friends.is_empty() and not by_id.has(sid):
				row.status = "not_friend"
			else:
				row.status = "invite"
				invite.append(row)
			seen[sid] = true
		rows.append(row)
	return { "rows": rows, "invite": invite, "self": self_n, "guests": joined_n + invite.size() }


## Rein: mehr als drei Gäste? Steam erlaubt es, empfiehlt aber höchstens vier Spieler.
static func limit_warning(guests: int) -> String:
	if guests <= STEAM_GUESTS:
		return ""
	return "Steam empfiehlt Remote Play Together für bis zu 4 Spieler (du und 3 Gäste). Mit %d Gästen geht es trotzdem, kann aber ruckeln." % guests


## Rein: Ergebnis der Einladung in die rows übernehmen (status invited | joined | failed).
## res: { joined: [Steam-IDs], results: { Steam-ID: { ok, skipped, reason } }, ok, text }.
static func apply_result(rows: Array, res: Dictionary) -> Array:
	var out: Array = []
	var results: Dictionary = res.get("results", {}) if res.get("results") is Dictionary else {}
	var joined: Array = res.get("joined", []) if res.get("joined") is Array else []
	for r in rows:
		var row: Dictionary = (r as Dictionary).duplicate()
		if str(row.status) == "invite":
			var e: Dictionary = results.get(str(row.steam), {})
			if str(e.get("skipped", "")) == "joined" or joined.has(str(row.steam)):
				row.status = "joined"
			elif bool(e.get("ok", false)):
				row.status = "invited"
			else:
				row.status = "failed"
				row["reason"] = str(e.get("reason", "")) if str(e.get("reason", "")) != "" else str(res.get("text", ""))
		out.append(row)
	return out


## Rein: Zeile für die Mitteilung, z. B. „3 eingeladen: Paul, Mira, Kai · 1 ohne Steam-Zuordnung“.
static func summary(rows: Array) -> String:
	var invited: Array = []
	var n := {}
	for r in rows:
		var st := str(r.get("status", ""))
		if st == "invited":
			invited.append(str(r.get("name", "")))
		else:
			n[st] = int(n.get(st, 0)) + 1
	var parts := PackedStringArray()
	if not invited.is_empty():
		parts.append(TranslationServer.translate("%d eingeladen: %s" % [invited.size(), ", ".join(PackedStringArray(invited))]))
	else:
		parts.append(TranslationServer.translate("Niemand eingeladen"))
	for k in [["joined", "schon dabei", "schon dabei"], ["failed", "ging nicht", "gingen nicht"],
			["unmapped", "ohne Steam-Zuordnung", "ohne Steam-Zuordnung"], ["not_friend", "kein Steam-Freund", "keine Steam-Freunde"],
			["excluded", "nicht eingeladen", "nicht eingeladen"]]:
		var c := int(n.get(k[0], 0))
		if c > 0:
			parts.append(Lang.count(c, k[1], k[2]))
	return " · ".join(parts)


## Rein: Erklärung für die, die Uzai nicht einladen kann (unten in der Leiste).
static func explain(rows: Array) -> String:
	var unm := rows.filter(func(r): return str(r.status) == "unmapped").map(func(r): return str(r.name))
	var nf := rows.filter(func(r): return str(r.status) == "not_friend").map(func(r): return str(r.name))
	var out := PackedStringArray()
	if not unm.is_empty():
		out.append("%s: Steam-Freund wählen (A)." % ", ".join(PackedStringArray(unm)))
	if not nf.is_empty() or not unm.is_empty():
		out.append("Einladen geht nur an Steam-Freunde. Wer noch keiner ist, muss dir erst eine Freundschaftsanfrage schicken (oder du ihm) – Steams Gast-Link für Leute ohne Freundschaft gibt Steam an andere Programme nicht heraus.")
	return " ".join(out)


# --- Senden ------------------------------------------------------------------------------------

## Wer laut Steam schon in der Sitzung ist (aus der letzten Einladung), je Spiel.
static var _joined := { "game": "", "ids": [] }


static func note_joined(ids: Array) -> void:
	_joined = { "game": str(Launcher.current.get("id", "")), "ids": ids.map(func(x): return str(x)) }


static func joined_now() -> Array:
	if not Launcher.in_game or str(_joined.game) != str(Launcher.current.get("id", "")):
		return []
	return _joined.ids


## Deine Steam-ID (angemeldet oder unter Konten eingetragen), "" wenn unbekannt.
static func my_steam() -> String:
	var id := SteamChat.my_id() if SteamChat.logged_in() else ""
	if id == "":
		id = str(Config.get_value("accounts.steam_id", "")).strip_edges()
	return id if id.is_valid_int() and id.length() >= 16 else ""


## Alle Einladungen schicken: im Demo-Modus nur zum Ansehen (alle klappen), sonst über den Helfer.
static func send(invite: Array) -> Dictionary:
	var ids: Array = invite.map(func(r): return str(r.steam))
	if Voice.demo or Social.demo:
		var tree := Engine.get_main_loop() as SceneTree
		var res := { "ok": true, "text": "", "joined": [], "results": {} }
		for id in ids:
			await tree.create_timer(0.35).timeout
			res.results[id] = { "ok": true, "skipped": "", "reason": "" }
		return res
	return await RemotePlay.send_invites(ids)


## Können wir gerade einladen, und wie heißt der Knopf? { show, ok, label, why }.
## show: Knopf zeigen · ok: Einladen geht jetzt (sonst erklärt why, was fehlt).
static func availability() -> Dictionary:
	var label := "Alle im Call zu Remote Play einladen"
	if str(Voice.channel.get("guild_id", "")) == "" and Voice.members.size() > 2:
		label = "Ganze Gruppe zu Remote Play einladen"
	var others := Voice.members.filter(func(m): return not bool(m.get("me", false)) and not bool(m.get("bot", false)))
	if not Launcher.in_game or others.is_empty():
		return { "show": false, "ok": false, "label": label, "why": "" }
	if RemotePlay.can_invite():
		return { "show": true, "ok": true, "label": label, "why": "" }
	if RemotePlay.possible_for(Launcher.current):
		return { "show": true, "ok": false, "label": label,
			"why": "%s läuft ohne Remote Play Together. Beende es und starte es über die Spieloptionen mit „Mit Remote Play Together starten“ – dann geht das Einladen hier." % Library.display_title(Launcher.current) }
	return { "show": false, "ok": false, "label": label, "why": "" }

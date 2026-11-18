extends RefCounted
## Freundschaftsanfragen (Punkt 11): eingehende und gesendete Anfragen von Steam (über Uzais eigene
## Verbindung zu Steam, ClientFriendsList) und Discord (Social SDK) in einer Liste. Annehmen und
## Ablehnen gibt es nur auf Knopfdruck (Social.answer_request); Gesendete stehen nur da. Hier
## steht die reine Logik – ohne Netz, darum testbar (tests/logic_anfragen.gd).
##
## Ein Eintrag: { key, source (steam|discord), id, dir (in|out), name, avatar, username }.

const IN := "in"
const OUT := "out"
## Steams Beziehung zu einer Person (EFriendRelationship): 2 = Anfrage an dich, 4 = von dir gesendet.
const STEAM_IN := 2
const STEAM_OUT := 4
## So viele schon gemeldete Anfragen merkt sich Uzai (keine Mitteilung zweimal).
const SEEN_MAX := 300


## Steam: Beziehungen (Steam-ID -> 2 oder 4) und was Uzai über die Personen weiß (Steam-ID ->
## { name, avatar }). Ohne bekannten Namen steht „Steam-Nutzer“ da, bis die Abfrage antwortet.
static func from_steam(rels: Dictionary, people: Dictionary) -> Array:
	var out: Array = []
	for k in rels:
		var id := str(k)
		var rel := int(rels[k])
		if not id.is_valid_int() or not (rel in [STEAM_IN, STEAM_OUT]):
			continue
		var p: Dictionary = people.get(id, {})
		out.append({ "key": "steam:" + id, "source": "steam", "id": id, "dir": IN if rel == STEAM_IN else OUT,
			"name": str(p.get("name", "")) if str(p.get("name", "")) != "" else "Steam-Nutzer", "avatar": str(p.get("avatar", "")), "username": "" })
	return out


## Discord: Personen aus dem Social SDK (wie DiscordChat.parse_friends sie liefert) je Richtung.
static func from_discord(incoming: Array, outgoing: Array) -> Array:
	var out: Array = []
	for pair in [[incoming, IN], [outgoing, OUT]]:
		for f in pair[0]:
			if not (f is Dictionary) or str(f.get("id", "")) == "":
				continue
			var name_ := str(f.get("name", ""))
			if name_ == "":
				name_ = str(f.get("username", ""))
			if name_ == "":
				name_ = "Discord-Nutzer"
			out.append({ "key": "discord:" + str(f.id), "source": "discord", "id": str(f.id), "dir": pair[1],
				"name": name_, "avatar": str(f.get("avatar", "")), "username": str(f.get("username", "")) })
	return out


## Eingehende zuerst (die wollen eine Antwort), dann gesendete; jeweils nach Namen.
static func sorted(list: Array) -> Array:
	var out := list.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a.dir) != str(b.dir):
			return str(a.dir) == IN
		var c := str(a.name).naturalnocasecmp_to(str(b.name))
		return c < 0 if c != 0 else str(a.key) < str(b.key)
	)
	return out


static func incoming(list: Array, source := "") -> Array:
	return list.filter(func(r: Dictionary) -> bool: return str(r.dir) == IN and (source == "" or str(r.source) == source))


static func outgoing(list: Array, source := "") -> Array:
	return list.filter(func(r: Dictionary) -> bool: return str(r.dir) == OUT and (source == "" or str(r.source) == source))


## Hat man dieser Person eine Anfrage geschickt? (per ID, sonst per Name) – für den Zustand an der
## Person selbst; eine eigene Liste gesendeter Anfragen gibt es nicht mehr.
static func sent_to(list: Array, source: String, id: String, name: String) -> bool:
	for r in outgoing(list, source):
		if (id != "" and str(r.get("id", "")) == id) or (id == "" and name != "" and str(r.get("name", "")).to_lower() == name.to_lower()):
			return true
	return false


## Eingehende Anfragen, die noch nie gemeldet wurden (seen: Schlüssel schon gemeldeter). Nur mit
## Namen – sonst erst, wenn die Abfrage den Namen gebracht hat.
static func to_announce(list: Array, seen: Array) -> Array:
	return incoming(list).filter(func(r: Dictionary) -> bool: return not seen.has(str(r.key)) and not (str(r.source) == "steam" and str(r.name) == "Steam-Nutzer"))


## Gemeldete merken, die ältesten fallen bei mehr als SEEN_MAX heraus.
static func remember(seen: Array, keys: Array) -> Array:
	var out := seen.duplicate()
	for k in keys:
		if not out.has(str(k)):
			out.append(str(k))
	return out.slice(maxi(0, out.size() - SEEN_MAX))


## Steams Antwort auf „Annehmen“ (EResult aus ClientAddFriendResponse) als Satz; "" = geklappt.
static func steam_error(eresult: int) -> String:
	match eresult:
		1:
			return ""
		25:
			return "Deine Steam-Freundesliste ist voll."
		40:
			return "Steam lässt das nicht zu: Einer von euch hat den anderen blockiert."
		_:
			return "Steam hat abgelehnt. Später noch einmal versuchen."


## Kurzer Satz unter dem Namen in der Liste.
static func line(r: Dictionary) -> String:
	if str(r.dir) == IN:
		return "Möchte mit dir befreundet sein"
	return "Anfrage gesendet"

extends RefCounted
## „Das Zimmer wächst mit deinem Spielen“ (Punkt 131 d): Meilensteine schalten Figuren,
## Möbel und Sachen fürs Haustier frei – nur durchs Spielen, nie durch Bezahlen (R6). Die Zahlen kommen
## aus den Abzeichen (Badges.facts: Spielzeit, gespielte Spiele, Spiele zu 100 %, Erfolge, Serien
## …); hier stehen nur die Schwellen und was sie freigeben. Reine Logik, ohne Fenster testbar.
##
## Gesperrt ist nur, was hier steht – alles andere ist von Anfang an frei. Was gesperrt ist, zeigt
## der Editor mit Schloss und Bedingung (zum Vorfreuen), getragen wird es erst, wenn es frei ist.

## id, Zahl (Badges.facts), Schwelle, Text der Bedingung, Freigaben ["feld:kennung", "moebel:id"].
const LISTE := [
	{ "id": "stunde_1", "fact": "hours_total", "ab": 1, "wie": "Die erste Stunde gespielt", "frei": ["moebel:tierkorb"] },
	{ "id": "stunden_10", "fact": "hours_total", "ab": 10, "wie": "10 Stunden gespielt", "frei": ["person:juna"] },
	{ "id": "stunden_100", "fact": "hours_total", "ab": 100, "wie": "100 Stunden gespielt", "frei": ["moebel:lavalampe"] },
	{ "id": "spiele_50", "fact": "games_played", "ab": 50, "wie": "50 Spiele gespielt", "frei": ["moebel:neonschild"] },
	{ "id": "platin_1", "fact": "perfect", "ab": 1, "wie": "Das erste Spiel mit allen Erfolgen", "frei": ["person:sara"] },
	{ "id": "erfolge_100", "fact": "ach_total", "ab": 100, "wie": "100 Erfolge freigeschaltet", "frei": ["person:max", "tier_muster:sterne"] },
	{ "id": "serie_7", "fact": "streak_best", "ab": 7, "wie": "7 Tage in Folge gespielt", "frei": ["person:jonas"] },
	{ "id": "nacht_1", "fact": "night_sessions", "ab": 1, "wie": "Die erste lange Nacht", "frei": ["person:nele"] },
	{ "id": "retro_3", "fact": "retro_systems", "ab": 3, "wie": "3 Konsolen im Emulator gespielt", "frei": ["person:leon"] },
	{ "id": "zusammen_1", "fact": "together", "ab": 1, "wie": "Das erste Spiel mit Freunden", "frei": ["tier_halsband:tuch"] },
]

## Anzeigenamen der freigegebenen Sachen (für die Mitteilung).
const NAMEN := {
	"moebel:tierkorb": "Tierkörbchen", "person:juna": "Juna als Figur", "moebel:lavalampe": "Lavalampe", "moebel:neonschild": "Leuchtschild",
	"person:sara": "Sara als Figur", "person:max": "Max als Figur", "tier_muster:sterne": "Sternenfell", "person:jonas": "Jonas als Figur",
	"person:nele": "Nele als Figur", "person:leon": "Leon als Figur", "tier_halsband:tuch": "Halstuch",
}


## Welche Meilensteine sind erreicht? facts wie Badges.facts.
static func erreicht(facts: Dictionary) -> Array:
	var out: Array = []
	for m in LISTE:
		var v: Variant = facts.get(str(m.fact), 0)
		if (v is int or v is float) and float(v) >= float(m.ab):
			out.append(str(m.id))
	return out


## Alle Freigaben, die einen Meilenstein brauchen: "feld:kennung" → Meilenstein-id.
static func gesperrt_alle() -> Dictionary:
	var out := {}
	for m in LISTE:
		for f in m.frei:
			out[str(f)] = str(m.id)
	return out


## Ist diese Sache frei? schluessel z. B. "kopf:kranz", "moebel:lavalampe". Was keinen
## Meilenstein braucht, ist immer frei.
static func ist_frei(schluessel: String, erreichte: Array) -> bool:
	var g := gesperrt_alle()
	return not g.has(schluessel) or str(g[schluessel]) in erreichte


## Bedingung als Text, „“ wenn frei.
static func bedingung(schluessel: String, erreichte: Array) -> String:
	var g := gesperrt_alle()
	if not g.has(schluessel) or str(g[schluessel]) in erreichte:
		return ""
	return str(info(str(g[schluessel])).get("wie", ""))


static func info(id: String) -> Dictionary:
	for m in LISTE:
		if str(m.id) == id:
			return m
	return {}


## Fortschritt eines Meilensteins (0..1) aus den Zahlen.
static func fortschritt(id: String, facts: Dictionary) -> float:
	var m := info(id)
	if m.is_empty():
		return 0.0
	var v: Variant = facts.get(str(m.fact), 0)
	return clampf(float(v) / float(m.ab), 0.0, 1.0) if (v is int or v is float) else 0.0


## Getragenes, das (noch) nicht frei ist, fällt auf den Standard zurück. felder wie
## FigurDaten.FIGUR_FELDER; praefix "" für die Figur, "tier_" für das Haustier.
static func nur_freies(werte: Dictionary, felder: Array, erreichte: Array, praefix := "") -> Dictionary:
	var out := werte.duplicate()
	for e in felder:
		var k := str(e[0])
		if out.has(k) and not ist_frei(praefix + k + ":" + str(out[k]), erreichte):
			out[k] = str(e[4])
	return out


## Was seit der letzten Meldung neu ist: [Meilenstein-ids]. gemeldet: schon gemeldete.
static func neu(erreichte: Array, gemeldet: Array) -> Array:
	var out: Array = []
	for id in erreichte:
		if not (id in gemeldet):
			out.append(id)
	return out


## Text der Mitteilung für neue Meilensteine: [Titel, Zeile].
static func meldung(neue: Array) -> Array:
	if neue.is_empty():
		return ["", ""]
	if neue.size() == 1:
		var m := info(str(neue[0]))
		var dinge: Array = []
		for f in m.frei:
			dinge.append(TranslationServer.translate(str(NAMEN.get(str(f), f))))
		return [TranslationServer.translate("Neu für dein Zimmer: %s") % ", ".join(dinge), TranslationServer.translate(str(m.wie))]
	var n := 0
	for id in neue:
		n += (info(str(id)).get("frei", []) as Array).size()
	return [TranslationServer.translate("%d neue Sachen für dein Zimmer") % n, TranslationServer.translate("Freigeschaltet durchs Spielen")]

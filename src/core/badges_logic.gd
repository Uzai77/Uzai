extends RefCounted
## Profil-Level und Abzeichen – die reine Logik ohne Oberfläche und ohne Netz (Tests:
## tests/logic_abzeichen). Badges (badges.gd) sammelt die Zahlen, hier wird daraus Level,
## Stufe je Abzeichen und was neu ist.
##
## Uzai-Punkte: jeder Erfolg zählt nach Seltenheit 10 bis 100 Punkte (points_for_rarity, wie die
## Erfolgs-Pop-ups in unlocks.gd), jede
## Spielstunde 2 Punkte, jede Abzeichen-Stufe 25/50/100/250. Daraus das Level: Level 1 bei 0
## Punkten, jeder Schritt braucht rund 10 % mehr als der vorige (ab Level 36 gleichbleibend
## 6.000 – so geht es ohne Ende weiter, ohne dass es unerreichbar wird).
##
## Abzeichen: ein Satz kuratierter Familien mit vier Stufen (Bronze, Silber, Gold, Platin).
## Jede Familie liest eine Zahl (fact) und vergleicht sie mit ihren vier Schwellen.

const Lang := preload("res://src/core/lang.gd")

const TIER_NAMES := ["", "Bronze", "Silber", "Gold", "Platin"]
const TIER_POINTS := [0, 25, 50, 100, 250]
const POINTS_PER_HOUR := 2
const DEFAULT_POINTS := 20           ## Erfolg ohne bekannte Seltenheit (wie Unlocks.UNKNOWN_POINTS)
const RARITY_POINTS := [[50.0, 10], [20.0, 20], [10.0, 30], [5.0, 50], [1.0, 75], [0.0, 100]]
const LEVEL_BASE := 200.0
const LEVEL_GROWTH := 1.1
const LEVEL_CAP := 6000

const CATS := [
	["zeit", "Spielzeit", "Stunden je Plattform"],
	["erfolge", "Erfolge", "freigeschaltet und selten"],
	["komplett", "Komplett", "bis zum letzten Erfolg"],
	["vielfalt", "Vielfalt", "Plattformen und Spiele"],
	["sozial", "Gemeinsam", "mit Freunden und festgehalten"],
	["treue", "Treue", "Serien, Tage und Level"],
	["retro", "Retro", "RetroAchievements"],
]

## Plattform-Gruppen für die Spielzeit: Gruppe -> Systeme der Bibliothek.
const PLATFORMS := {
	"ps1": ["ps1"], "ps2": ["ps2"], "gc": ["gc"], "wii": ["wii", "wiiu"], "n64": ["n64"],
	"16bit": ["snes", "megadrive", "nes", "mastersystem", "pce"], "switch": ["switch"],
	"handheld": ["gba", "gb", "gbc", "nds", "3ds", "psp", "gamegear"], "steam": ["steam"],
	"pc": ["pc", "epic", "ea", "gog", "ubisoft", "battlenet", "xboxpc", "amazon", "itch", "riot"],
}

## id, Kategorie, Name, Symbol (Zeichnung im Abzeichen), Zahl (fact), Schwellen, Einheit
## [eins, mehrere], Titel je Stufe (%s = Schwelle), Beschreibung, Bedingung fürs Zeigen
## (need: "plat:<gruppe>" – Plattform in der Bibliothek, "ra" – RetroAchievements verbunden),
## mark: kurzer Text im Abzeichen (Plattformen).
const DEFS := [
	{ "id": "zeit_ps1", "cat": "zeit", "name": "PlayStation", "glyph": "disc", "mark": "PS1", "fact": "hours_ps1", "tiers": [10, 50, 100, 500],
		"unit": ["Stunde", "Stunden"], "title": "%s Stunden PS1", "desc": "Spielzeit mit PlayStation-Spielen.", "need": "plat:ps1" },
	{ "id": "zeit_ps2", "cat": "zeit", "name": "PlayStation 2", "glyph": "disc", "mark": "PS2", "fact": "hours_ps2", "tiers": [10, 50, 100, 500],
		"unit": ["Stunde", "Stunden"], "title": "%s Stunden PS2", "desc": "Spielzeit mit PlayStation-2-Spielen.", "need": "plat:ps2" },
	{ "id": "zeit_gc", "cat": "zeit", "name": "GameCube", "glyph": "disc", "mark": "GC", "fact": "hours_gc", "tiers": [10, 50, 100, 500],
		"unit": ["Stunde", "Stunden"], "title": "%s Stunden GameCube", "desc": "Spielzeit mit GameCube-Spielen.", "need": "plat:gc" },
	{ "id": "zeit_wii", "cat": "zeit", "name": "Wii", "glyph": "disc", "mark": "Wii", "fact": "hours_wii", "tiers": [10, 50, 100, 500],
		"unit": ["Stunde", "Stunden"], "title": "%s Stunden Wii", "desc": "Spielzeit mit Wii- und Wii-U-Spielen.", "need": "plat:wii" },
	{ "id": "zeit_n64", "cat": "zeit", "name": "Nintendo 64", "glyph": "cart", "mark": "N64", "fact": "hours_n64", "tiers": [10, 50, 100, 500],
		"unit": ["Stunde", "Stunden"], "title": "%s Stunden N64", "desc": "Spielzeit mit Nintendo-64-Spielen.", "need": "plat:n64" },
	{ "id": "zeit_16bit", "cat": "zeit", "name": "8 und 16 Bit", "glyph": "cart", "mark": "16", "fact": "hours_16bit", "tiers": [10, 50, 100, 500],
		"unit": ["Stunde", "Stunden"], "title": "%s Stunden 8/16 Bit", "desc": "Spielzeit mit SNES, NES, Mega Drive, Master System und PC Engine.",
		"need": "plat:16bit" },
	{ "id": "zeit_switch", "cat": "zeit", "name": "Switch", "glyph": "cart", "mark": "NSW", "fact": "hours_switch", "tiers": [10, 50, 100, 500],
		"unit": ["Stunde", "Stunden"], "title": "%s Stunden Switch", "desc": "Spielzeit mit Switch-Spielen.", "need": "plat:switch" },
	{ "id": "zeit_handheld", "cat": "zeit", "name": "Handhelds", "glyph": "handheld", "mark": "", "fact": "hours_handheld", "tiers": [10, 50, 100, 500],
		"unit": ["Stunde", "Stunden"], "title": "%s Stunden unterwegs", "desc": "Spielzeit mit Game Boy, DS, 3DS, PSP und Game Gear.", "need": "plat:handheld" },
	{ "id": "zeit_steam", "cat": "zeit", "name": "Steam", "glyph": "monitor", "mark": "", "fact": "hours_steam", "tiers": [10, 50, 100, 500],
		"unit": ["Stunde", "Stunden"], "title": "%s Stunden Steam", "desc": "Spielzeit in deiner Steam-Bibliothek (wie Steam sie zählt).", "need": "plat:steam" },
	{ "id": "zeit_pc", "cat": "zeit", "name": "PC", "glyph": "desktop", "mark": "", "fact": "hours_pc", "tiers": [10, 50, 100, 500], "unit": ["Stunde", "Stunden"],
		"title": "%s Stunden PC", "desc": "Spielzeit mit PC-Spielen außerhalb von Steam (Epic, EA, eigene).", "need": "plat:pc" },
	{ "id": "zeit_total", "cat": "zeit", "name": "Dauerbrenner", "glyph": "clock", "mark": "", "fact": "hours_total", "tiers": [50, 250, 1000, 5000],
		"unit": ["Stunde", "Stunden"], "title": "%s Stunden insgesamt", "desc": "Spielzeit über alle Plattformen zusammen." },
	{ "id": "ach_total", "cat": "erfolge", "name": "Sammler", "glyph": "trophy", "mark": "", "fact": "ach_total", "tiers": [1, 10, 100, 1000],
		"unit": ["Erfolg", "Erfolge"], "title": "%s Erfolge", "titles": ["Erster Erfolg"], "desc": "Freigeschaltete Erfolge bei Steam und RetroAchievements." },
	{ "id": "ach_rare", "cat": "erfolge", "name": "Seltenheit", "glyph": "diamond", "mark": "", "fact": "ach_rare10", "tiers": [1, 10, 50, 200],
		"unit": ["seltener Erfolg", "seltene Erfolge"], "title": "%s seltene Erfolge", "titles": ["Erster seltener Erfolg"],
		"desc": "Erfolge, die weniger als 10 % der Spieler haben." },
	{ "id": "ach_ultra", "cat": "erfolge", "name": "Elite", "glyph": "crown", "mark": "", "fact": "ach_rare1", "tiers": [1, 5, 25, 100],
		"unit": ["Erfolg unter 1 %", "Erfolge unter 1 %"], "title": "%s Erfolge unter 1 %%", "titles": ["Unter 1 %"],
		"desc": "Erfolge, die weniger als 1 % der Spieler haben." },
	{ "id": "ach_games", "cat": "erfolge", "name": "Breit aufgestellt", "glyph": "star", "mark": "", "fact": "ach_games", "tiers": [5, 25, 100, 250],
		"unit": ["Spiel", "Spiele"], "title": "Erfolge in %s Spielen", "desc": "Spiele, in denen du mindestens einen Erfolg hast." },
	{ "id": "perfect", "cat": "komplett", "name": "Perfektionist", "glyph": "check", "mark": "", "fact": "perfect", "tiers": [1, 5, 25, 100],
		"unit": ["Spiel", "Spiele"], "title": "%s Spiele zu 100 %%", "titles": ["Erstes Spiel zu 100 %"],
		"desc": "Spiele mit allen Erfolgen (Steam und RetroAchievements)." },
	{ "id": "beaten", "cat": "komplett", "name": "Abspann", "glyph": "flag", "mark": "", "fact": "ra_beaten", "tiers": [1, 5, 20, 50], "unit": ["Spiel", "Spiele"],
		"title": "%s Spiele durchgespielt", "titles": ["Erster Abspann"], "desc": "Durchgespielt laut RetroAchievements.", "need": "ra" },
	{ "id": "platforms", "cat": "vielfalt", "name": "Weltenbummler", "glyph": "layers", "mark": "", "fact": "platforms", "tiers": [2, 4, 7, 10],
		"unit": ["Plattform", "Plattformen"], "title": "%s Plattformen", "desc": "Plattformen, auf denen du mindestens eine Stunde gespielt hast." },
	{ "id": "games_played", "cat": "vielfalt", "name": "Bibliothekar", "glyph": "grid", "mark": "", "fact": "games_played", "tiers": [10, 50, 150, 400],
		"unit": ["Spiel", "Spiele"], "title": "%s Spiele gespielt", "desc": "Verschiedene Spiele mit Spielzeit." },
	{ "id": "retro_systems", "cat": "vielfalt", "name": "Zeitreisender", "glyph": "retro", "mark": "", "fact": "retro_systems", "tiers": [1, 3, 6, 10],
		"unit": ["Konsole", "Konsolen"], "title": "%s Konsolen im Emulator", "titles": ["Erste Konsole im Emulator"],
		"desc": "Verschiedene Konsolen, die du über Emulatoren gespielt hast." },
	{ "id": "together", "cat": "sozial", "name": "Zusammen", "glyph": "friends", "mark": "", "fact": "together", "tiers": [1, 5, 15, 40],
		"unit": ["Spiel", "Spiele"], "title": "%s Spiele mit Freunden", "titles": ["Erstes Spiel mit Freunden"],
		"desc": "Spiele, die ein Freund zur selben Zeit gespielt hat – oder über Remote Play zusammen." },
	{ "id": "remote_play", "cat": "sozial", "name": "Couch-Koop", "glyph": "controller", "mark": "", "fact": "remote_play", "tiers": [1, 5, 20, 50],
		"unit": ["Sitzung", "Sitzungen"], "title": "%s Mal Remote Play", "titles": ["Erstes Remote Play"],
		"desc": "Spiele, zu denen du Freunde über Remote Play Together eingeladen hast." },
	{ "id": "captures", "cat": "sozial", "name": "Festgehalten", "glyph": "camera", "mark": "", "fact": "captures", "tiers": [1, 10, 50, 200],
		"unit": ["Aufnahme", "Aufnahmen"], "title": "%s Bilder und Clips", "titles": ["Erste Aufnahme"],
		"desc": "Bildschirmfotos und Clips, die du über den Guide gespeichert hast." },
	{ "id": "streak", "cat": "treue", "name": "Am Ball", "glyph": "flame", "mark": "", "fact": "streak_best", "tiers": [3, 7, 14, 30], "unit": ["Tag", "Tage"],
		"title": "%s Tage in Folge", "desc": "Längste Serie von Tagen hintereinander, an denen du über Uzai gespielt hast." },
	{ "id": "days", "cat": "treue", "name": "Stammgast", "glyph": "calendar", "mark": "", "fact": "days_played", "tiers": [7, 30, 100, 365],
		"unit": ["Tag", "Tage"], "title": "%s Spieltage", "desc": "Tage, an denen du über Uzai gespielt hast." },
	{ "id": "marathon", "cat": "treue", "name": "Marathon", "glyph": "hourglass", "mark": "", "fact": "longest_session", "tiers": [2, 4, 6, 10],
		"unit": ["Stunde am Stück", "Stunden am Stück"], "title": "%s Stunden am Stück", "desc": "Längste einzelne Spielsitzung über Uzai." },
	{ "id": "night", "cat": "treue", "name": "Nachteule", "glyph": "moon", "mark": "", "fact": "night_sessions", "tiers": [1, 5, 20, 50],
		"unit": ["Nacht", "Nächte"], "title": "%s Nächte nach Mitternacht", "titles": ["Erste lange Nacht"],
		"desc": "Sitzungen, die zwischen Mitternacht und 5 Uhr enden." },
	{ "id": "level", "cat": "treue", "name": "Uzai-Veteran", "glyph": "spark", "mark": "", "fact": "level", "tiers": [5, 10, 25, 50], "unit": ["Level", "Level"],
		"title": "Level %s", "desc": "Dein Uzai-Level aus allen Punkten.", "no_points": true },
	{ "id": "ra_unlocked", "cat": "retro", "name": "Retro-Jäger", "glyph": "retro", "mark": "", "fact": "ra_unlocked", "tiers": [10, 100, 500, 2000],
		"unit": ["Erfolg", "Erfolge"], "title": "%s RetroAchievements", "desc": "Freigeschaltete Erfolge bei RetroAchievements.", "need": "ra" },
	{ "id": "ra_hardcore", "cat": "retro", "name": "Hardcore", "glyph": "bolt", "mark": "", "fact": "ra_hardcore", "tiers": [1, 50, 250, 1000],
		"unit": ["Erfolg", "Erfolge"], "title": "%s Erfolge im Hardcore-Modus", "titles": ["Erster Hardcore-Erfolg"],
		"desc": "Erfolge im Hardcore-Modus (ohne Speicherstände und Zurückspulen).", "need": "ra" },
	{ "id": "ra_mastered", "cat": "retro", "name": "Meister", "glyph": "medal", "mark": "", "fact": "ra_mastered", "tiers": [1, 5, 15, 50],
		"unit": ["Spiel", "Spiele"], "title": "%s Spiele gemeistert", "titles": ["Erstes Spiel gemeistert"],
		"desc": "Spiele mit allen Erfolgen bei RetroAchievements.", "need": "ra" },
]


# --- Punkte und Level ----------------------------------------------------------------------

## Uzai-Punkte eines Erfolgs nach Seltenheit (Anteil der Spieler in %), genau wie die
## Erfolgs-Pop-ups (Unlocks.points_for): ≥ 50 → 10, 20–50 → 20, 10–20 → 30, 5–10 → 50,
## 1–5 → 75, unter 1 → 100; unbekannt (< 0) → DEFAULT_POINTS.
static func points_for_rarity(pct: float) -> int:
	if pct < 0.0:
		return DEFAULT_POINTS
	for t in RARITY_POINTS:
		if pct >= float(t[0]):
			return int(t[1])
	return 100


## RetroAchievements wie Unlocks.points_for_ra: mit Seltenheit wie oben, sonst aus den RA-Punkten.
static func points_for_ra(ra_points: int, pct := -1.0) -> int:
	if pct >= 0.0:
		return points_for_rarity(pct)
	if ra_points <= 2:
		return 10
	if ra_points <= 5:
		return 20
	if ra_points <= 10:
		return 30
	if ra_points <= 25:
		return 50
	if ra_points <= 50:
		return 75
	return 100


## Punkte für den Schritt von Level lv auf lv + 1 (glatt auf 10 gerundet).
static func level_step(lv: int) -> int:
	var raw := LEVEL_BASE * pow(LEVEL_GROWTH, float(maxi(lv, 1) - 1))
	return mini(int(round(raw / 10.0)) * 10, LEVEL_CAP)


## Punkte, ab denen Level lv beginnt (Level 1: 0).
static func level_start(lv: int) -> int:
	var t := 0
	for i in range(1, maxi(lv, 1)):
		t += level_step(i)
	return t


## Level aus Punkten: { level, into (Punkte im Level), need (Punkte des Schritts), left (bis zum
## nächsten), frac (0…1), start, next }
static func level_of(points: int) -> Dictionary:
	var p := maxi(points, 0)
	var lv := 1
	var start := 0
	while true:
		var step := level_step(lv)
		if p < start + step:
			return { "level": lv, "into": p - start, "need": step, "left": start + step - p,
				"frac": float(p - start) / float(step), "start": start, "next": start + step }
		start += step
		lv += 1
		if lv > 100000:
			break
	return { "level": lv, "into": 0, "need": 1, "left": 1, "frac": 0.0, "start": start, "next": start + 1 }


## „Noch 120 Punkte bis Level 13“
static func level_left_text(points: int) -> String:
	var l := level_of(points)
	return "Noch %s %s bis Level %d" % [num(int(l.left)), "Punkt" if int(l.left) == 1 else "Punkte", int(l.level) + 1]


## Punkte aus den Zahlen: Erfolge (ach_points), Spielzeit, Abzeichen-Stufen.
## tiers: id -> Stufe (0…4). Ergebnis: { total, ach, play, badges }
static func points_total(facts: Dictionary, tiers: Dictionary) -> Dictionary:
	var ach := int(facts.get("ach_points", 0))
	var play := int(floor(float(facts.get("hours_total", 0.0)))) * POINTS_PER_HOUR
	var bp := 0
	for d in DEFS:
		if bool(d.get("no_points", false)):
			continue
		var t := int(tiers.get(str(d.id), 0))
		for i in range(1, t + 1):
			bp += int(TIER_POINTS[i])
	return { "total": ach + play + bp, "ach": ach, "play": play, "badges": bp }


## Erfolgspunkte, auch für alles, was vor Uzai freigeschaltet wurde: bekannte Spiele (mit
## Seltenheit je Erfolg) genau, der Rest der freigeschalteten Erfolge mit DEFAULT_POINTS.
## known: Spiel -> { n (freigeschaltet mit Liste), p (Punkte), r10, r1 }; unlocked: alle
## freigeschalteten Erfolge. Ergebnis: { points, rare10, rare1, known }
static func ach_points(known: Dictionary, unlocked: int) -> Dictionary:
	var p := 0
	var n := 0
	var r10 := 0
	var r1 := 0
	for k in known.keys():
		var e: Dictionary = known[k]
		p += int(e.get("p", 0))
		n += int(e.get("n", 0))
		r10 += int(e.get("r10", 0))
		r1 += int(e.get("r1", 0))
	var rest := maxi(0, unlocked - n)
	return { "points": p + rest * DEFAULT_POINTS, "rare10": r10, "rare1": r1, "known": n }


## Zusammenfassung einer Erfolgsliste (Format von Achievements.steam_game/ra_game) für known.
static func game_summary(res: Dictionary) -> Dictionary:
	var n := 0
	var p := 0
	var r10 := 0
	var r1 := 0
	var ra := str(res.get("source", "")) == "ra"
	for a in res.get("list", []):
		if not (a is Dictionary) or not bool(a.get("unlocked", false)):
			continue
		var pct := float(a.get("rarity", -1.0))
		n += 1
		p += points_for_ra(int(a.get("points", 0)), pct) if ra else points_for_rarity(pct)
		if pct >= 0.0 and pct < 10.0:
			r10 += 1
		if pct >= 0.0 and pct < 1.0:
			r1 += 1
	return { "n": n, "p": p, "r10": r10, "r1": r1 }


# --- Abzeichen -----------------------------------------------------------------------------

static func def_of(id: String) -> Dictionary:
	for d in DEFS:
		if str(d.id) == id:
			return d
	return {}


static func cat_name(cat: String) -> String:
	for c in CATS:
		if str(c[0]) == cat:
			return str(c[1])
	return ""


## Erreichte Stufe (0 = noch keine, 1 Bronze … 4 Platin).
static func tier_for(d: Dictionary, value: float) -> int:
	var t := 0
	var ts: Array = d.get("tiers", [])
	for i in ts.size():
		if value + 0.0001 >= float(ts[i]):
			t = i + 1
	return t


## Alle Stufen aus den Zahlen; gespeicherte (earned) gehen nie verloren.
static func evaluate(facts: Dictionary, earned := {}) -> Dictionary:
	var out := {}
	for d in DEFS:
		var id := str(d.id)
		out[id] = maxi(tier_for(d, float(facts.get(str(d.fact), 0.0))), int(earned.get(id, 0)))
	return out


## Level und Abzeichen zusammen ausrechnen. Das Level hängt an den Abzeichen-Punkten und das
## Abzeichen „Uzai-Veteran“ am Level – das Veteran-Abzeichen bringt deshalb selbst keine Punkte.
## Ergebnis: { tiers, points (wie points_total), level (wie level_of), facts }
static func compute(facts_in: Dictionary, earned := {}) -> Dictionary:
	var facts := facts_in.duplicate()
	var tiers := evaluate(facts, earned)
	var pts := points_total(facts, tiers)
	var lv := level_of(int(pts.total))
	facts["level"] = int(lv.level)
	tiers = evaluate(facts, earned)
	return { "tiers": tiers, "points": pts, "level": lv, "facts": facts }


## Was sich gegenüber dem gespeicherten Stand geändert hat: neue Stufen ([{ id, tier }], höchste
## Stufe je Abzeichen) und ein neues Level. first: allererster Lauf – alles gilt als schon da
## (kein Pop-up, nur die einmalige Zusammenfassung).
static func diff(old_tiers: Dictionary, new_tiers: Dictionary, old_level: int, new_level: int, first: bool) -> Dictionary:
	var fresh: Array = []
	for id in new_tiers.keys():
		var t := int(new_tiers[id])
		if t > int(old_tiers.get(id, 0)):
			fresh.append({ "id": str(id), "tier": t, "from": int(old_tiers.get(id, 0)) })
	fresh.sort_custom(func(a, b): return int(a.tier) > int(b.tier) if int(a.tier) != int(b.tier) else str(a.id) < str(b.id))
	var up := new_level > old_level and old_level > 0
	if first:
		return { "popups": [], "level_up": false, "summary": count_earned(new_tiers), "fresh": fresh, "level": new_level }
	return { "popups": fresh, "level_up": up, "summary": 0, "fresh": fresh, "level": new_level }


## Wie viele Abzeichen (mit mindestens Bronze) es gibt.
static func count_earned(tiers: Dictionary) -> int:
	var n := 0
	for id in tiers.keys():
		if int(tiers[id]) > 0:
			n += 1
	return n


## Ob ein Abzeichen auf der Seite steht: Plattformen nur, wenn es Spiele dafür gibt, Retro nur
## mit RetroAchievements – schon verdiente stehen immer da.
static func visible(d: Dictionary, ctx: Dictionary, tier: int) -> bool:
	if tier > 0:
		return true
	var need := str(d.get("need", ""))
	if need == "":
		return true
	if need == "ra":
		return bool(ctx.get("ra", false))
	if need.begins_with("plat:"):
		return (ctx.get("platforms", {}) as Dictionary).has(need.substr(5))
	return true


## Titel einer Stufe: „100 Stunden PS2“, „Erster Erfolg“; Stufe 0: der Name.
static func tier_title(d: Dictionary, tier: int) -> String:
	if tier <= 0:
		return str(d.get("name", ""))
	var ts: Array = d.get("tiers", [])
	var t := mini(tier, ts.size())
	var named: Array = d.get("titles", [])
	if t - 1 < named.size() and str(named[t - 1]) != "":
		return str(named[t - 1])
	return str(d.get("title", "%s")) % num(int(ts[t - 1]))


## Fortschritt zur nächsten Stufe: { value, goal, frac, text („37/50 Stunden“), done (Platin) }.
## Die Einheit kommt schon übersetzt hinein: „37/50“ davor passt auf kein Muster des Katalogs.
static func progress(d: Dictionary, value: float, tier: int) -> Dictionary:
	var ts: Array = d.get("tiers", [])
	var unit: Array = d.get("unit", ["", ""])
	var v := floori(value + 0.0001)
	if tier >= ts.size():
		var top := int(ts[ts.size() - 1])
		return { "value": v, "goal": top, "frac": 1.0, "done": true,
			"text": "%s %s" % [num(v), TranslationServer.translate(str(unit[0]) if v == 1 else str(unit[1]), "1" if v == 1 else "n")] }
	var goal := int(ts[tier])
	var prev := int(ts[tier - 1]) if tier > 0 else 0
	var frac := clampf((value - prev) / float(maxi(goal - prev, 1)), 0.0, 1.0)
	return { "value": v, "goal": goal, "frac": frac, "done": false,
		"text": "%s/%s %s" % [num(mini(v, goal)), num(goal), TranslationServer.translate(str(unit[0]) if goal == 1 else str(unit[1]), "1" if goal == 1 else "n")] }


# --- Zahlen aus den Daten ------------------------------------------------------------------

## Plattform-Gruppe eines Systems ("" wenn keine).
static func platform_of(system: String) -> String:
	for k in PLATFORMS.keys():
		if (PLATFORMS[k] as Array).has(system):
			return str(k)
	return ""


## Spielzeit je Plattform (Stunden) aus der Bibliothek: games = [{ system, secs }].
## steam_minutes: Spielzeit der ganzen Steam-Bibliothek, wenn bekannt (auch nicht installierte).
## Ergebnis: { hours_<gruppe>, hours_total, platforms (mit ≥ 1 Std.), games_played, retro_systems,
##   present: Gruppe -> true (Plattformen mit Spielen), top_<gruppe>: System mit der meisten
##   Spielzeit in Gruppen mit mehreren Systemen (für das Logo im Abzeichen, z. B. „megadrive“) }
static func playtime_facts(games: Array, steam_minutes := 0, steam_played := 0) -> Dictionary:
	var per := {}
	var per_sys := {}
	var present := {}
	var played := 0
	var steam_lib_played := 0
	var emu := {}
	for g in games:
		var sys := str(g.get("system", ""))
		var grp := platform_of(sys)
		var secs := int(g.get("secs", 0))
		if grp != "":
			present[grp] = true
			per[grp] = int(per.get(grp, 0)) + secs
			per_sys[sys] = int(per_sys.get(sys, 0)) + secs
		if secs >= 600:
			if grp == "steam":
				steam_lib_played += 1
			else:
				played += 1
			if str(g.get("source", "")) == "rom" and secs >= 1800:
				emu[sys] = true
	if steam_minutes * 60 > int(per.get("steam", 0)):
		per["steam"] = steam_minutes * 60
		present["steam"] = true
	var out := { "present": present }
	var total := 0.0
	var plats := 0
	for k in PLATFORMS.keys():
		var h := float(per.get(k, 0)) / 3600.0
		out["hours_" + str(k)] = h
		total += h
		if h >= 1.0:
			plats += 1
	out["hours_total"] = total
	out["platforms"] = plats
	out["games_played"] = played + maxi(steam_lib_played, steam_played)
	out["retro_systems"] = emu.size()
	for k in PLATFORMS.keys():
		var best := ""
		var best_s := 0
		for sys in PLATFORMS[k]:
			var s := int(per_sys.get(sys, 0))
			if s > best_s:
				best = str(sys)
				best_s = s
		if best != "" and (PLATFORMS[k] as Array).size() > 1:
			out["top_" + str(k)] = best
	return out


## Serien und Gewohnheiten aus den Sitzungen ([{ id, at (Ende, Unix), secs }]); bias: Zeitzone
## in Sekunden. { streak_best, days_played, night_sessions, longest_session (Std.) }
static func session_facts(sessions: Array, bias: int) -> Dictionary:
	var days := {}
	var night := 0
	var longest := 0
	for s in sessions:
		var end := int(s.get("at", 0))
		var secs := int(s.get("secs", 0))
		if end <= 0 or secs <= 0:
			continue
		var local := end + bias
		days[int(floor(float(local) / 86400.0))] = true
		var hour := int(posmod(local, 86400) / 3600)
		if hour < 5 and secs >= 900:
			night += 1
		longest = maxi(longest, secs)
	var keys: Array = days.keys()
	keys.sort()
	var best := 0
	var run := 0
	var last := -10
	for d in keys:
		run = run + 1 if int(d) == last + 1 else 1
		last = int(d)
		best = maxi(best, run)
	return { "streak_best": best, "days_played": keys.size(), "night_sessions": night, "longest_session": float(longest) / 3600.0 }


## Zahlen, die nie zurückgehen sollen (Sitzungen sind gekappt, Listen nur im Speicher): je Zahl
## das Größere aus gespeichert und jetzt.
static func keep_best(saved: Dictionary, now: Dictionary) -> Dictionary:
	var out := now.duplicate()
	for k in saved.keys():
		var v: Variant = saved[k]
		if (v is int or v is float) and (not out.has(k) or float(v) > float(out[k])):
			out[k] = v
	return out


## 6.873 statt 6873
static func num(n: int) -> String:
	return Lang.tausender(n)

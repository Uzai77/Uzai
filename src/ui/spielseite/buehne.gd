extends RefCounted
## Die Bühne der Spielseite und die Blöcke des Profils – reine Logik ohne Knoten, geprüft in
## tests/logic_buehne.gd: die Woche aus den Runden (sieben Tage, älteste zuerst), die beiden leisen
## Zeilen unter dem Titel (was es ist, was es dir ist), Texte der Bühnenkarten (Erfolge, Freunde,
## Spielstände), welche Karten überhaupt erscheinen, und Kürzen von hinten, damit eine Zeile nie
## abbricht. Alles kommt aus Uzais eigenen Daten; nichts davon geht ins Netz.

const Lang := preload("res://src/core/lang.gd")

const TAGE_KURZ := ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
const KARTEN_MAX := 4            ## so viele Karten hat die Bühnenreihe höchstens


## Tag (Ortszeit) einer Unix-Zeit; bias: Zeitzone in Sekunden.
static func tag(unix: int, bias: int) -> int:
	return int(floor(float(unix + bias) / 86400.0))


## Die letzten sieben Tage aus den Runden ({ id, at = Ende, secs }), älteste zuerst, heute zuletzt.
## gid: nur dieses Spiel, "" alle. Eine Runde zählt zum Tag ihres Endes (wie die Seite Spielzeit).
## { tage: [s0 … s6], labels: ["Mo" … "Heute"], gesamt, gespielt (Tage mit Zeit), max }
static func woche(sessions: Array, gid: String, now: int, bias: int) -> Dictionary:
	var heute := tag(now, bias)
	var tage: Array = [0, 0, 0, 0, 0, 0, 0]
	for se in sessions:
		if not (se is Dictionary):
			continue
		if gid != "" and str(se.get("id", "")) != gid:
			continue
		var secs := int(se.get("secs", 0))
		var ende := int(se.get("at", 0))
		if secs <= 0 or ende <= 0:
			continue
		var i := tag(ende, bias) - (heute - 6)
		if i >= 0 and i < 7:
			tage[i] = int(tage[i]) + secs
	var labels: Array = []
	var gesamt := 0
	var gespielt := 0
	var mx := 0
	for i in 7:
		var d := heute - 6 + i
		labels.append("Heute" if i == 6 else TAGE_KURZ[(d + 4) % 7])
		gesamt += int(tage[i])
		if int(tage[i]) > 0:
			gespielt += 1
		mx = maxi(mx, int(tage[i]))
	return { "tage": tage, "labels": labels, "gesamt": gesamt, "gespielt": gespielt, "max": mx }


## Kurze Zeit für große Zahlen: „45 Min.“, „3,5 Std.“, „120 Std.“, „1.284 Std.“; 0: „0 Std.“
static func zeit_kurz(secs: int) -> String:
	if secs <= 0:
		return "0 Std."
	var m := floori(secs / 60.0)
	if m < 60:
		return "%d Min." % maxi(m, 1)
	var h := float(secs) / 3600.0
	if h < 10.0:
		var t := Lang.dec("%.1f" % h)
		return (t.trim_suffix(",0").trim_suffix(".0")) + " Std."
	return "%s Std." % tausender(int(round(h)))


## 6.873 statt 6873
static func tausender(n: int) -> String:
	return Lang.tausender(n)


## Die Zeile „was es ist“: Emulator-Spiel „PlayStation 2 · PCSX2 · Bild: CRT“, Steam „Genre, Genre ·
## Studio“, sonst der Name der Quelle. Leeres fällt weg, ein „ · “ im Wert wird zum Komma.
static func oben(sys_name: String, emu_name: String, filter_name: String, genres: PackedStringArray, developer: String, quelle := "") -> Array:
	var parts: Array = []
	if sys_name != "":
		parts.append(sys_name)
	if emu_name != "":
		parts.append(emu_name)
	if filter_name != "":
		# Erst übersetzen, dann umformen: „CRT, 480 Zeilen“ steht in keinem Katalog, „CRT · 480 Zeilen“ schon.
		parts.append("Bild: %s" % str(TranslationServer.translate(filter_name)).replace(" · ", ", "))
	if not genres.is_empty():
		parts.append(", ".join(genres.slice(0, 2)))
	if developer != "":
		parts.append(developer)
	if parts.is_empty() and quelle != "":
		parts.append(quelle)
	return parts


## Die Zeile „was es dir ist“: Spielzeit, zuletzt, nicht installiert, Platz („182 GB frei auf C:“).
## last_ago: fertiger Text („heute“, „gestern“, „am 12.03.“), "" ohne.
static func unten(secs: int, last_ago: String, installed: bool, note := "") -> Array:
	var parts: Array = []
	if secs > 0:
		parts.append(zeit_kurz(secs) + " gespielt")
	else:
		parts.append("Noch nicht gespielt")
	if last_ago != "":
		parts.append(TranslationServer.translate("zuletzt %s") % TranslationServer.translate(last_ago))
	if not installed:
		parts.append("nicht installiert")
	if note != "":
		parts.append(note)
	return parts


## „Heute“, „Gestern“, „vor 3 Tagen“ – klein geschrieben, wie im Satz; Datum mit „am“.
static func zuletzt_text(ago: String) -> String:
	if ago == "":
		return ""
	if ago.contains(".") and not ago.begins_with("Vor"):
		return "am " + ago
	return ago.substr(0, 1).to_lower() + ago.substr(1)


## Teile zu einer Zeile fügen, hintere fallen weg, bis sie in width passen (nie „…“ in der Mitte).
## breite(text) -> float misst den Text. Der erste Teil bleibt immer.
static func passend(parts: Array, width: float, breite: Callable, sep := "  ·  ") -> String:
	var keep: Array = parts.filter(func(p: Variant) -> bool: return str(p) != "")
	while keep.size() > 1:
		var t := sep.join(PackedStringArray(keep.map(func(p: Variant) -> String: return str(p))))
		if float(breite.call(t)) <= width:
			return t
		keep.pop_back()
	return str(keep[0]) if not keep.is_empty() else ""


## Freunde-Karte aus Social.playing: { titel, sub, beitreten }. Leer ohne Freunde.
static func freunde(list: Array) -> Dictionary:
	if list.is_empty():
		return {}
	var names: Array = []
	var join := false
	for f in list:
		if f is Dictionary:
			names.append(str(f.get("name", "")))
			if str(f.get("lobby", "")) != "" or str(f.get("server", "")) != "":
				join = true
	var titel := ""
	var sub := ""
	if names.size() == 1:
		titel = "%s spielt gerade" % names[0]
		sub = "Beitreten möglich" if join else "Im Spiel"
	else:
		titel = "%d Freunde spielen gerade" % names.size()
		sub = ", ".join(PackedStringArray(names.slice(0, 3))) + (" …" if names.size() > 3 else "")
	return { "titel": titel, "sub": sub, "beitreten": join }


## Erfolge-Karte aus Achievements.for_game: { wert: „29 von 42“, frac, sub }. Leer ohne Erfolge.
## sub: zuletzt freigeschaltet (Name · wann) – sonst der nächste offene; alles frei: „Alle
## freigeschaltet“. ago(unix) -> String liefert „Heute“, „Gestern“ …
static func erfolge(ach: Dictionary, ago: Callable) -> Dictionary:
	var total := int(ach.get("total", 0))
	if total <= 0:
		return {}
	var got := int(ach.get("unlocked", 0))
	var list: Array = ach.get("list", [])
	var sub := ""
	if got >= total:
		sub = "Alle freigeschaltet"
	else:
		var last: Dictionary = {}
		var nxt: Dictionary = {}
		for a in list:
			if not (a is Dictionary):
				continue
			if a.get("unlocked", false):
				if last.is_empty() or int(a.get("date", 0)) > int(last.get("date", 0)):
					last = a
			elif nxt.is_empty() and not a.get("hidden", false):
				nxt = a
		if not last.is_empty() and int(last.get("date", 0)) > 0:
			sub = "Zuletzt: %s · %s" % [str(last.get("title", "")), zuletzt_text(str(ago.call(int(last.date))))]
		elif not last.is_empty():
			sub = "Zuletzt: %s" % str(last.get("title", ""))
		elif not nxt.is_empty():
			sub = "Als Nächstes: %s" % str(nxt.get("title", ""))
	return { "wert": "%d von %d" % [got, total], "frac": clampf(float(got) / float(total), 0.0, 1.0), "sub": sub, "voll": got >= total }


## Welche Karten die Bühnenreihe zeigt, in dieser Reihenfolge: zeit (Spielzeit > 0 oder Runden),
## erfolge (bekannt oder zu erwarten), freunde (spielen gerade), stand (Spielstände). Höchstens
## KARTEN_MAX. lage: { secs, runden, erfolge_bekannt, erfolge_moeglich, freunde, staende }
static func karten(lage: Dictionary) -> Array:
	var out: Array = []
	if int(lage.get("secs", 0)) > 0 or int(lage.get("runden", 0)) > 0:
		out.append("zeit")
	if bool(lage.get("erfolge_bekannt", false)) or bool(lage.get("erfolge_moeglich", false)):
		out.append("erfolge")
	if int(lage.get("freunde", 0)) > 0:
		out.append("freunde")
	if int(lage.get("staende", 0)) > 0:
		out.append("stand")
	return out.slice(0, KARTEN_MAX)


## Texte der kleinen Pillen unter den Knöpfen (src/ui/spielseite/buehne_chip.gd): { wert, wort } –
## der Wert kräftig vorn, das Wort leise dahinter. Gleiche Arten wie karten().
const NAME_MAX := 16             ## längere Namen werden in der Pille gekürzt

## Spielzeit: die Woche („3 Std.“ „diese Woche“); ohne Spiel in dieser Woche nur „Spielzeit“
## (die Summe steht schon in der Zeile unter dem Titel).
static func pille_zeit(woche_secs: int) -> Dictionary:
	if woche_secs > 0:
		return { "wert": zeit_kurz(woche_secs), "wort": "diese Woche" }
	return { "wert": "", "wort": "Spielzeit" }


## Erfolge: „29 / 42“ „Erfolge“; unbekannt (lädt noch): „…“.
static func pille_erfolge(got: int, total: int) -> Dictionary:
	if total <= 0:
		return { "wert": "…", "wort": "Erfolge" }
	return { "wert": "%d / %d" % [clampi(got, 0, total), total], "wort": "Erfolge" }


## Freunde: „Mira“ „spielt gerade“, mehrere „3 Freunde“ „spielen gerade“. Leer ohne Freunde.
## roh: Der Wert ist ein Name und wird nie übersetzt.
static func pille_freunde(list: Array) -> Dictionary:
	var names: Array = list.filter(func(f: Variant) -> bool: return f is Dictionary)
	if names.is_empty():
		return {}
	if names.size() == 1:
		var n := str((names[0] as Dictionary).get("name", ""))
		if n.length() > NAME_MAX:
			n = n.substr(0, NAME_MAX - 1).strip_edges() + "…"
		return { "wert": n, "wort": "spielt gerade", "roh": true }
	return { "wert": Lang.count(names.size(), "Freund", "Freunde"), "wort": "spielen gerade" }


## Spielstände: „2“ „Spielstände“, einer: „1“ „Spielstand“. Leer ohne.
static func pille_staende(n: int) -> Dictionary:
	if n <= 0:
		return {}
	return { "wert": str(n), "wort": "Spielstand" if n == 1 else "Spielstände" }


## Eine Zeile unter dem Verlauf der Runden statt vier Kacheln: „Längste Runde 3 Std. 10 Min. am
## 12. März · meist abends · noch 5 Std. bis 125 Std.“ st: SessionSummary.per_game; dur(secs),
## date(unix) -> String; daypart(hour) -> [Name, Symbol]; marks(secs) -> [erreicht, nächste].
static func runden_zeile(st: Dictionary, total: int, dur: Callable, date: Callable, daypart: Callable, marks: Array) -> Array:
	var parts: Array = []
	if st.is_empty():
		return parts
	var n := int(st.get("count", 0))
	parts.append("%s · im Schnitt %s" % [Lang.count(n, "Runde", "Runden"), str(dur.call(int(st.get("avg", 0))))])
	var lg: Dictionary = st.get("longest", {})
	if int(lg.get("secs", 0)) > 0:
		parts.append("längste %s am %s" % [str(dur.call(int(lg.secs))), str(date.call(int(lg.get("at", 0))))])
	if int(st.get("peak", -1)) >= 0:
		var part: Array = daypart.call(int(st.peak))
		parts.append("meist %s" % str(part[0]).to_lower())
	if marks.size() == 2 and int(marks[1]) > 0:
		parts.append("noch %s bis %d Std." % [str(dur.call(int(marks[1]) * 3600 - total)), int(marks[1])])
	return parts


## Vergleich mit einem Freund (Profil des Freundes): zwei Werte zu Anteilen 0…1 der größeren Zahl.
## { a, b } mit a = du, b = Freund; beide 0 → beide 0.
static func anteile(a: float, b: float) -> Dictionary:
	var mx := maxf(a, b)
	if mx <= 0.0:
		return { "a": 0.0, "b": 0.0 }
	return { "a": clampf(a / mx, 0.0, 1.0), "b": clampf(b / mx, 0.0, 1.0) }


## Die Vitrine des Profils: Favoriten (bis limit), sonst die meistgespielten; { titel, extra, list }.
## games: sichtbare Spiele mit "favorite" und playtime(g) -> int.
static func vitrine(games: Array, playtime: Callable, limit := 12) -> Dictionary:
	var favs: Array = games.filter(func(g: Variant) -> bool: return g is Dictionary and bool(g.get("favorite", false)))
	if not favs.is_empty():
		favs.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(playtime.call(x)) > int(playtime.call(y)))
		return { "titel": "Vitrine", "extra": Lang.count(favs.size(), "Favorit", "Favoriten"), "list": favs.slice(0, limit) }
	var top: Array = games.filter(func(g: Variant) -> bool: return g is Dictionary and int(playtime.call(g)) > 0)
	top.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(playtime.call(x)) > int(playtime.call(y)))
	if top.is_empty():
		return {}
	return { "titel": "Vitrine", "extra": "am meisten gespielt", "list": top.slice(0, limit) }


## Freunde fürs Profil: online und im Spiel zuerst, dann die übrigen; bis limit; { list, online }.
static func freunde_reihe(list: Array, limit := 8) -> Dictionary:
	var order := { "game": 0, "online": 1, "away": 2, "idle": 2, "busy": 3, "dnd": 3, "offline": 9 }
	var sorted: Array = list.filter(func(f: Variant) -> bool: return f is Dictionary)
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa := int(order.get(str(a.get("state", "")), 9))
		var ob := int(order.get(str(b.get("state", "")), 9))
		if oa != ob:
			return oa < ob
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0)
	var online := sorted.filter(func(f: Dictionary) -> bool: return int(order.get(str(f.get("state", "")), 9)) < 9).size()
	return { "list": sorted.slice(0, limit), "online": online }

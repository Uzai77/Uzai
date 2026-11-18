extends Node
## Logik des Bereichs Profil/Erfolge ohne Oberfläche: Seltenheitsstufen, Prozent- und Datumstexte,
## Beispieldaten, Summen über beide Quellen, Fehlerergebnis, Steam-Zählung über die Bibliothek
## (perfekte Spiele), Profil-XML, Spielzeit-Rückblick.
## Aufruf: godot --headless --path . res://tests/logic_erfolge.tscn

const Ach := preload("res://src/core/achievements.gd")
const Rarity := preload("res://src/ui/components/ach/rarity.gd")
const PT := preload("res://src/ui/sections/playtime_page.gd")
const WC := preload("res://src/ui/components/week_chart.gd")
const Emblem := preload("res://src/ui/components/ach/emblem.gd")
const Profile := preload("res://src/ui/sections/profile_page.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Seltenheit")
	check(Ach.rarity_tier(-1.0) == -1, "ohne Anteil keine Stufe")
	check(Ach.rarity_tier(0.4) == 3 and Ach.rarity_tier(4.99) == 3, "unter 5 % ultra selten")
	check(Ach.rarity_tier(5.0) == 2 and Ach.rarity_tier(14.9) == 2, "5 bis 15 % sehr selten")
	check(Ach.rarity_tier(15.0) == 1 and Ach.rarity_tier(34.9) == 1, "15 bis 35 % selten")
	check(Ach.rarity_tier(35.0) == 0 and Ach.rarity_tier(100.0) == 0, "ab 35 % häufig")
	check(Ach.rarity_name(3) == "Ultra selten" and Ach.rarity_name(0) == "Häufig" and Ach.rarity_name(-1) == "", "Namen der Stufen")
	check(Ach.pct_text(3.14) == "3,1 %", "Komma statt Punkt (%s)" % Ach.pct_text(3.14))
	check(Ach.pct_text(0.05) == "< 0,1 %", "sehr kleine Anteile (%s)" % Ach.pct_text(0.05))
	check(Ach.pct_text(42.4) == "42 %" and Ach.pct_text(-1.0) == "", "ganze Prozent ab 10 (%s)" % Ach.pct_text(42.4))
	check(Ach.award_name("mastered") == "Gemeistert" and Ach.award_name("beaten-softcore") == "Durchgespielt" and Ach.award_name("") == "",
			"Auszeichnungen auf Deutsch")
	var c0 := Rarity.color(0)
	var c3 := Rarity.color(3)
	check(c3 == UzTheme.col("accent") and c0 == UzTheme.col("muted"), "Farben aus dem Schema")

	print("Texte")
	var now := int(Time.get_unix_time_from_system())
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var y := int(Time.get_date_dict_from_unix_time(now + bias).year)
	var oct := int(Time.get_unix_time_from_datetime_string("%d-10-12T12:00:00" % y)) - bias
	check(Rarity.date(oct) == "12. Okt.", "Datum ohne Jahr im laufenden Jahr (%s)" % Rarity.date(oct))
	var old := int(Time.get_unix_time_from_datetime_string("%d-03-02T12:00:00" % (y - 2))) - bias
	check(Rarity.date(old) == "2. März %d" % (y - 2), "Datum mit Jahr (%s)" % Rarity.date(old))
	# Genau jetzt (nicht „vor 30 s“): kurz nach Mitternacht läge das sonst schon gestern.
	check(Rarity.when(now) == "Gerade eben" and Rarity.when(0) == "", "„Gerade eben“ und leer")
	check(Rarity.when(now - 40 * 86400).contains("."), "lange her: Datum statt „Vor x Wochen“ (%s)" % Rarity.when(now - 40 * 86400))

	print("Beispieldaten")
	var er := Achievements.demo_game("steam:1245620")
	check(int(er.total) == 42 and int(er.unlocked) == 29 and (er.list as Array).size() == 42, "Elden Ring: 29 von 42")
	var got := (er.list as Array).filter(func(a): return a.unlocked).size()
	check(got == 29, "freigeschaltete in der Liste stimmen (%d)" % got)
	var ordered := true
	var seen_locked := false
	var last_date := 1 << 62
	var last_rar := 1000.0
	for a in er.list:
		if a.unlocked:
			if seen_locked or int(a.date) > last_date:
				ordered = false
			last_date = int(a.date)
		else:
			seen_locked = true
			if float(a.rarity) > last_rar + 0.001:
				ordered = false
			last_rar = float(a.rarity)
	check(ordered, "frei zuerst (neueste oben), dann offen nach Seltenheit")
	check((er.list as Array).any(func(a): return a.get("hidden", false) and not a.unlocked), "ein geheimer offener Erfolg")
	check((er.list as Array).all(func(a): return float(a.rarity) > 0.0 and float(a.rarity) < 100.0), "Anteile im gültigen Bereich")
	var ok := Achievements.demo_game("ps2:30fa359a43774f")
	check(str(ok.source) == "ra" and int(ok.ra_id) > 0 and int(ok.points) <= int(ok.points_total) and int(ok.points) > 0, "Ōkami: Punkte von RetroAchievements")
	check(Achievements.demo_game("pc:gibtsnicht").is_empty(), "unbekanntes Spiel ohne Erfolge")
	check(Achievements.demo_game("steam:1245620") == er, "Beispiel wird nur einmal erzeugt")

	print("Summen")
	var keep_ra: Array = Achievements.ra_progress
	var keep_st: Array = Achievements.steam_progress
	Achievements.ra_progress = [{ "total": 10, "unlocked": 10 }, { "total": 20, "unlocked": 5 }, { "total": 0, "unlocked": 0 }]
	Achievements.steam_progress = [{ "total": 30, "unlocked": 15 }]
	var t: Dictionary = Achievements.totals()
	check(int(t.unlocked) == 30 and int(t.total) == 60, "Erfolge über beide Quellen (%d / %d)" % [int(t.unlocked), int(t.total)])
	check(int(t.games) == 3 and int(t.complete) == 1, "Spiele ohne Erfolge zählen nicht, eines komplett")
	Achievements.ra_progress = keep_ra
	Achievements.steam_progress = keep_st
	var e := Ach._net_error("steam", "Steam ist gerade nicht erreichbar.")
	check(int(e.total) == 0 and str(e.error) != "", "ohne Netz: Fehler statt „keine Erfolge“")
	check(Ach.steam_problem(0) == "Steam ist gerade nicht erreichbar." and Ach.steam_problem(403).contains("Konten")
			and Ach.steam_problem(502) == "Steam hat gerade Probleme.", "Steam-Fehler verständlich benannt")

	print("Perfekte Spiele (ganze Bibliothek)")
	var owned: Array = []
	var counts := {}
	for i in 12:
		owned.append({ "appid": 100 + i, "name": "Spiel %d" % i, "minutes": 0 if i == 11 else 60 * (i + 1), "last": 1000 + i })
	# 8 perfekte (darunter das ungespielte 11), eines ohne Erfolge, eines angefangen, eines nie geöffnet, eines ungezählt.
	for i in [0, 1, 2, 3, 4, 5, 6, 11]:
		counts[str(100 + i)] = { "m": 0, "u": 20, "t": 20, "at": 0 }
	counts["107"] = { "m": 0, "u": 0, "t": 0, "at": 0 }
	counts["108"] = { "m": 0, "u": 5, "t": 20, "at": 0 }
	counts["109"] = { "m": 0, "u": 0, "t": 10, "at": 0 }
	var st := Ach.steam_totals(owned, counts)
	check(int(st.perfect_count) == 8 and (st.perfect as Array).size() == 8, "8 perfekte Spiele, nicht nur die zuletzt gespielten (%d)" % int(st.perfect_count))
	check(int(st.perfect[0].appid) == 111, "zuletzt gespieltes perfektes Spiel zuerst")
	check(int(st.games) == 12 and int(st.played) == 11 and int(st.counted) == 11 and int(st.with_ach) == 10, "Spiele, gespielt, gezählt, mit Erfolgen")
	check(int(st.started) == 9 and int(st.unlocked) == 165, "angefangen und freigeschaltet (%d)" % int(st.unlocked))
	check(int(st.total) == 190, "Quote nur über gespielte/angefangene Spiele (%d)" % int(st.total))
	check(absf(float(st.avg) - 100.0 * (8.0 + 0.25) / 9.0) < 0.01, "Ø Fortschritt je angefangenem Spiel (%.1f)" % float(st.avg))
	check(int(st.minutes) == 60 * 66, "Spielzeit über alle Spiele")
	var keep_stats: Dictionary = Achievements.steam_stats
	Achievements.ra_progress = [{ "total": 10, "unlocked": 10 }]
	Achievements.steam_progress = [{ "source": "steam", "appid": 100, "total": 20, "unlocked": 20 }]
	Achievements.steam_stats = {}
	check(int(Achievements.totals().complete) == 2, "vor der Zählung: nur zuletzt gespielte (alter Stand)")
	Achievements.steam_stats = st
	var t2: Dictionary = Achievements.totals()
	check(int(t2.complete) == 9 and int(t2.unlocked) == 175, "nach der Zählung: alle 8 Steam-Spiele + RA (%d)" % int(t2.complete))
	check(Achievements.steam_perfect().size() == 8, "steam_perfect aus der Zählung")
	Achievements.steam_stats = keep_stats
	Achievements.ra_progress = keep_ra
	Achievements.steam_progress = keep_st
	var cache := { "100": { "m": 60, "u": 1, "t": 2, "at": 1000 }, "101": { "m": 60, "u": 1, "t": 2, "at": 1000 } }
	var todo := Ach.count_todo(owned.slice(0, 3) + [owned[11]], cache, 2000, false)
	check(todo.size() == 2 and int(todo[0].appid) == 101 and int(todo[1].appid) == 102, "nur neu zählen, was sich geändert hat (Spielzeit) oder fehlt")
	check(Ach.count_todo([owned[11]], {}, 2000, true).size() == 1 and Ach.count_todo([owned[11]], {}, 2000, false).is_empty(), "ungespielte nur mit Sammelabfrage")
	check(Ach.count_todo([owned[0]], { "100": { "m": 60, "u": 1, "t": 2, "at": 0 } }, Ach.COUNT_MAX_AGE + 10, false).size() == 1, "alter Stand wird erneuert")
	var pr := Ach.parse_progress({ "response": { "achievement_progress": [
		{ "appid": 620, "unlocked": 51, "total": 51, "percentage": 100, "all_unlocked": true },
		{ "appid": 570, "unlocked": 0, "total": 0, "percentage": 0, "all_unlocked": false },
		{ "appid": 440, "unlocked": 12, "total": 520, "all_unlocked": false }] } })
	check(pr.size() == 3 and int(pr[620].u) == 51 and int(pr[440].t) == 520 and int(pr[570].t) == 0, "Sammelabfrage lesen")
	check(Ach.parse_progress(null).is_empty() and Ach.parse_progress({ "response": {} }).is_empty(), "Sammelabfrage ohne Antwort: leer (dann einzeln)")
	var pa := Ach.parse_player_ach(
			{ "ok": true, "code": 200, "data": { "playerstats": { "success": true, "achievements": [{ "achieved": 1 }, { "achieved": 0 }, { "achieved": 1 }] } } })
	check(str(pa.state) == "ok" and int(pa.u) == 2 and int(pa.t) == 3, "Einzelabfrage: 2 von 3")
	pa = Ach.parse_player_ach({ "ok": false, "code": 400, "data": { "playerstats": { "error": "Requested app has no stats", "success": false } } })
	check(str(pa.state) == "nostats", "Spiel ohne Erfolge")
	pa = Ach.parse_player_ach({ "ok": false, "code": 403, "data": { "playerstats": { "error": "Profile is not public", "success": false } } })
	check(str(pa.state) == "private", "Spieldetails privat")
	pa = Ach.parse_player_ach({ "ok": false, "code": 429, "data": null })
	check(str(pa.state) == "error" and int(pa.code) == 429, "Drosselung erkannt")
	var og := Ach.parse_owned_games(
			{ "response": { "game_count": 2, "games": [{ "appid": 10, "name": "A", "playtime_forever": 5, "rtime_last_played": 7 }, { "appid": 0 }] } })
	check(og.size() == 1 and int(og[0].minutes) == 5 and int(og[0].last) == 7, "Bibliothek lesen")
	check(Ach.parse_items({ "response": { "profile_background": { "image_large": "items/1245620/abc.jpg" } } }) == Ach.ITEM_IMG + "items/1245620/abc.jpg",
			"Profilhintergrund")
	check(Ach.parse_items({ "response": { "profile_background": {} } }) == "" and Ach.parse_items(null) == "", "ohne Hintergrund leer")
	var lists := [{ "appid": 1, "title": "A", "list": [{ "unlocked": true, "rarity": 0.5, "title": "a1", "desc": "", "icon": "", "date": 0 },
		{ "unlocked": true, "rarity": 0.6, "title": "a2", "desc": "", "icon": "", "date": 0 },
			{ "unlocked": true, "rarity": 0.7, "title": "a3", "desc": "", "icon": "", "date": 0 },
		{ "unlocked": false, "rarity": 0.1, "title": "zu", "desc": "", "icon": "", "date": 0 }] },
		{ "appid": 2, "title": "B", "list": [{ "unlocked": true, "rarity": 3.0, "title": "b1", "desc": "", "icon": "", "date": 0 }] }]
	var rar := Ach.rarest_of(lists, 10, 2)
	check(rar.size() == 3 and str(rar[0].title) == "a1" and str(rar[2].title) == "b1", "seltenste: freigeschaltete, je Spiel höchstens zwei")
	var keep_rp: Array = Achievements.ra_progress
	Achievements.ra_progress = [{ "award": "mastered", "total": 5, "unlocked": 5 }, { "award": "completed", "total": 5, "unlocked": 5 },
		{ "award": "beaten-hardcore", "total": 9, "unlocked": 4 }, { "award": "", "total": 9, "unlocked": 1 }]
	var rs := Achievements.ra_stats()
	check(int(rs.mastered) == 2 and int(rs.mastered_hc) == 1 and int(rs.beaten) == 3 and int(rs.games) == 4, "RetroAchievements: gemeistert und durchgespielt")
	Achievements.ra_progress = keep_rp

	print("Profil-XML")
	var xml := """<?xml version="1.0" encoding="UTF-8" standalone="yes"?><profile>
	<steamID64>76561197960435530</steamID64>
	<steamID><![CDATA[Robin]]></steamID>
	<onlineState>offline</onlineState>
	<privacyState>public</privacyState>
	<avatarFull><![CDATA[https://avatars.steamstatic.com/x_full.jpg]]></avatarFull>
	<memberSince>October 12, 2003</memberSince>
	<headline><![CDATA[]]></headline>
	<location><![CDATA[Seattle, WA, United States]]></location>
	<realname><![CDATA[Robin Walker]]></realname>
	<summary><![CDATA[Hallo &amp; willkommen!<br>Zweite Zeile <a href="https://x">Link</a> &quot;zitiert&quot;]]></summary>
	<groups><group><summary><![CDATA[Gruppentext]]></summary></group></groups>
</profile>"""
	var px := Ach.parse_profile_xml(xml)
	check(bool(px.ok) and bool(px.public), "öffentliches Profil erkannt")
	check(str(px.summary) == "Hallo & willkommen!\nZweite Zeile Link \"zitiert\"", "Info-Text ohne HTML (%s)" % str(px.summary).c_escape())
	check(str(px.realname) == "Robin Walker" and str(px.location) == "Seattle, WA, United States", "Klarname und Wohnort")
	var ms := Time.get_date_dict_from_unix_time(int(px.member_since))
	check(int(ms.year) == 2003 and int(ms.month) == 10 and int(ms.day) == 12, "Mitglied seit (englisch)")
	check(str(px.avatar).ends_with("x_full.jpg"), "Profilbild")
	var priv := Ach.parse_profile_xml("<profile><steamID64>1</steamID64><privacyState>private</privacyState><summary>geheim</summary></profile>")
	check(bool(priv.ok) and not bool(priv.public) and str(priv.summary) == "", "privat: kein Info-Text")
	var nf := Ach.parse_profile_xml("<response><error><![CDATA[The specified profile could not be found.]]></error></response>")
	check(not bool(nf.ok) and str(nf.error).contains("could not be found"), "unbekanntes Profil")
	check(not bool(Ach.parse_profile_xml("").ok), "ohne Antwort")
	var none := Ach.parse_profile_xml(
			xml.replace("Hallo &amp; willkommen!<br>Zweite Zeile <a href=\"https://x\">Link</a> &quot;zitiert&quot;", "No information given."))
	check(str(none.summary) == "", "„No information given.“ zählt nicht als Text")
	var de := Time.get_date_dict_from_unix_time(Ach.parse_member_since("4. September 2009"))
	check(int(de.year) == 2009 and int(de.month) == 9 and int(de.day) == 4, "Mitglied seit (deutsch)")
	check(Ach.parse_member_since("") == 0 and Ach.parse_member_since("irgendwann") == 0, "unlesbares Datum: 0")
	check(Ach.strip_html("a<br/>b<br />c&#39;s&nbsp;x") == "a\nb\nc's x", "Zeilenumbrüche und Zeichen")
	# Den Text schreibt ein Fremder in sein Profil: keine Steuerzeichen, kein Nullzeichen, keine umgedrehte Schreibrichtung.
	check(Ach.strip_html("A&#0;B&#8238;C&#27;D&#228;E&#9999999;F") == "ABCDäEF", "Zeichen-Nummern: nur Druckbares – " + Ach.strip_html("A&#0;B&#8238;C&#27;D&#228;E&#9999999;F").c_escape())
	check(Ach.strip_html("x &amp;lt;b&amp;gt; y") == "x &lt;b&gt; y", "„&amp;“ wird zuletzt gelesen (nichts doppelt)")
	check(Ach.parse_member_since("October 99, 2010") > 0, "unmöglicher Tag: trotzdem ein Datum")
	var dx := Ach.demo_extra(Ach.DEMO_ME)
	check(bool(dx.public) and str(dx.summary) != "" and int(dx.member_since) > 0, "Beispiel-Profil hat Info-Text")
	check(not bool(Ach.demo_extra("76561190000000007").public), "Beispiel: privates Profil")
	check(Profile.num(6873) == "6.873" and Profile.num(12) == "12" and Profile.num(1234567) == "1.234.567", "Tausenderpunkte")
	check(Profile.hours(412380) == "6.873 Std." and Profile.hours(90) == "1,5 Std." and Profile.hours(0) == "0 Std.",
			"Spielzeit in Stunden (%s)" % Profile.hours(412380))

	print("Spielzeit")
	check(PT.dur(30) == "< 1 Min." and PT.dur(45 * 60) == "45 Min.", "kurze Zeiten")
	check(PT.dur(2 * 3600 + 5 * 60) == "2 Std. 5 Min." and PT.dur(3 * 3600) == "3 Std.", "Stunden mit Minuten")
	check(PT.dur(1284 * 3600 + 120) == "1.284 Std.", "große Zahlen mit Punkt")
	check(WC._short(int(4.3 * 3600)) == "4,3 Std." and WC._short(59) == "1 Min.", "Säulen-Beschriftung (%s)" % WC._short(59))
	var p = PT.new()
	p._days = { 100: {}, 101: {}, 102: {}, 105: {}, 106: {} }
	check(p._best_streak() == 3, "längste Serie über Lücken hinweg (%d)" % p._best_streak())
	p._days = {}
	check(p._best_streak() == 0, "ohne Tage keine Serie")
	check(p._weekday(0) == 4 and p._weekday(3) == 0, "1.1.1970 war ein Donnerstag")

	print("Abzeichen")
	var pts := Emblem.rounded(Rect2(0, 0, 100, 100), 10.0, 6)
	check(pts.size() == 28, "abgerundetes Rechteck: 4 Ecken × 7 Punkte")
	var inside := true
	for q in pts:
		if q.x < -0.01 or q.y < -0.01 or q.x > 100.01 or q.y > 100.01:
			inside = false
	check(inside, "alle Punkte in der Fläche")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

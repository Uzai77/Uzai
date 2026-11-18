extends Node
## Blocker des Uzai-Browsers (src/core/browser_filter.gd): dieselbe Tabelle wie der Kern (tests/fixtures/browser_filter.json),
## Regeln aus dem Format, Muster-Vergleich, Kosmetik je Seite, die mitgelieferte Liste (Prüfsumme, lädt, sperrt
## bekannte Werbe-Domänen, verschont normale Seiten), Cookie-Regeln (Form, nie „akzeptieren“), das Filter-Skript.
## Aufruf: godot --headless --path . res://tests/logic_browser_filter.tscn

const F := preload("res://src/core/browser_filter.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	_tabelle()
	_format()
	_liste()
	_cookies()
	_skript()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _tabelle() -> void:
	print("Tabelle (gleich wie der Kern)")
	var tab: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/browser_filter.json"))
	check(tab is Dictionary, "Tabelle gelesen")
	var f = F.new()
	var n := 0
	for z in tab.regeln:
		if f.zeile_lesen(str(z)[0], str(z).substr(2)):
			n += 1
	check(n == (tab.regeln as Array).size(), "alle %d Regeln angenommen" % n)
	var falsch: Array = []
	for z in tab.faelle:
		var g: bool = f.gesperrt(str(z[0]), int(z[1]), str(z[2]))
		if g != bool(z[3]):
			falsch.append("%s (%d auf %s): %s" % [z[0], int(z[1]), z[2], g])
	check(falsch.is_empty(), "jeder Fall wie erwartet %s" % ("" if falsch.is_empty() else str(falsch)))
	check(f.kosmetik("news.example").size() == int(tab.kosmetik_news) and f.kosmetik("other.example").size() == int(tab.kosmetik_other),
		"Kosmetik je Seite (news %d, other %d)" % [f.kosmetik("news.example").size(), f.kosmetik("other.example").size()])
	check(not f.gesperrt("https://ads.example/x.js", 0, "news.example"), "Hauptdokument nie gesperrt")
	check(F.site("a.b.co.uk") == "b.co.uk" and F.site("x.example.com") == "example.com" and F.site("localhost") == "localhost", "Site aus dem Namen")
	check(F.host_von("https://user@Sub.Example.com:8443/a?b") == "sub.example.com" and F.host_von("kaputt") == "", "Name aus der Adresse")


func _format() -> void:
	print("Format")
	var f = F.new()
	for bad in ["div{color:red}", "a;b", "x url(a)", "/* */", "div:has(a)", "a\\b"]:
		check(not F.selektor_ok(bad), "Selektor abgelehnt: %s" % bad)
	check(F.selektor_ok(".ad-banner > div[data-ad]") and F.selektor_ok("#sponsored"), "normale Selektoren gehen")
	check(not f.zeile_lesen("p", "x"), "zu kurzes Muster abgelehnt")
	check(not f.zeile_lesen("p", "||a.de^|q|"), "unbekannter Typbuchstabe abgelehnt")
	check(not f.zeile_lesen("d", "nurname"), "Domäne ohne Punkt abgelehnt")
	check(not f.zeile_lesen("x", "egal"), "unbekannte Art abgelehnt")
	check(F.bestes_token("||ad.server.example/x*y") == "example", "längster Lauf als Token")
	check(F.bestes_token("ab/cd") == "", "kein Token unter 4 Zeichen")
	check(F.glob("a*c^", 0, "abbc/", 0, false) and not F.glob("a*c^", 0, "abbcd", 0, false)
			and F.glob("abc", 0, "abc", 0, true) and not F.glob("abc", 0, "abcd", 0, true), "Muster mit * ^ und Ende")
	check(f.zeile_lesen("p", "||a.example/x^|s3|b.example") and f.gesperrt("https://a.example/x?1", 3, "b.example") and not f.gesperrt("https://a.example/x?1", 3, "a.example")
		and not f.gesperrt("https://a.example/x?1", 4, "b.example"), "Flags: Typ, dritte Partei, Seite")
	check(f.zeile_lesen("p", "|https://c.example/*.gif|~s|") and f.gesperrt("https://c.example/a.gif", 4, "x.de") and not f.gesperrt("https://c.example/a.gif", 3, "x.de"),
		"Anfang-Anker und negierte Typen")
	check(not f.gesperrt("https://" + "a".repeat(9000) + ".de/", 3, "x.de"), "überlange Adresse: nicht gesperrt, kein Absturz")


func _liste() -> void:
	print("Mitgelieferte Liste")
	check(FileAccess.get_sha256(F.LISTE) == F.LISTE_SHA256, "Prüfsumme stimmt")
	var lizenz := FileAccess.get_file_as_string("res://assets/browser/filter/LIZENZ.txt")
	var helfer := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	check(lizenz.contains(F.LISTE_SHA256) and helfer.contains(F.LISTE_SHA256), "gleiche Prüfsumme in LIZENZ und Helfer")
	check(lizenz.contains("CC BY-SA 3.0") and lizenz.contains("easylist.to/pages/licence.html"), "Lizenz genannt")
	var t0 := Time.get_ticks_msec()
	var f = F.laden(F.LISTE)
	var ms := Time.get_ticks_msec() - t0
	check(f.regeln > 50000, "Liste geladen: %d Regeln in %d ms" % [f.regeln, ms])
	check(f.gesperrt("https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js", 3, "news.example") or f.gesperrt("https://www.googletagmanager.com/gtm.js", 3, "news.example"),
		"bekannte Werbe-/Tracker-Domäne gesperrt")
	check(not f.gesperrt("https://de.wikipedia.org/w/load.php?modules=startup", 3, "de.wikipedia.org"), "Wikipedia-Skript frei")
	check(not f.gesperrt("https://www.tagesschau.de/resources/assets/image/logo.svg", 4, "www.tagesschau.de"), "Logo einer Nachrichtenseite frei")
	check(not f.gesperrt("https://example.com/", 0, ""), "Hauptdokument frei")
	var k: Array = f.kosmetik("example.com")
	check(k.size() > 5000 and k.size() <= F.MAX_SELEKTOREN, "Kosmetik für eine Seite: %d Selektoren" % k.size())
	var t1 := Time.get_ticks_msec()
	for i in 1000:
		f.gesperrt("https://cdn%d.example/static/app.js?v=%d" % [i % 7, i], 3, "page%d.example" % (i % 3))
	check(Time.get_ticks_msec() - t1 < 6000, "1000 Entscheidungen in %d ms (GDScript-Zwilling; der Kern entscheidet in C#)" % (Time.get_ticks_msec() - t1))
	check(F.literal("/ad*banner^") == "banner" and F.literal("a.b^") == "a.b" and F.literal("*^") == "", "längstes wörtliches Stück")


func _cookies() -> void:
	print("Cookie-Regeln")
	var c: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/browser/filter/cookies.json"))
	check(c is Dictionary and c.has("dienste") and c.has("ablehnen") and c.has("nie") and c.has("banner"), "Datei gelesen")
	var gut := true
	for d in c.dienste:
		if not (d is Dictionary) or not F.selektor_ok(str(d.get("erkennen", ""))) or not (d.get("ablehnen", null) is Array):
			gut = false
			continue
		for a in d.ablehnen:
			if not F.selektor_ok(str(a)):
				gut = false
	check(gut and (c.dienste as Array).size() >= 15, "%d Dienste mit gültigen Selektoren" % (c.dienste as Array).size())
	# „nicht zustimmen“ enthält „zustimmen“, „disagree“ enthält „agree“: Das Skript nimmt erst die Ablehnen-Wörter aus
	# dem Text und sucht dann nach Akzeptieren-Wörtern – hier dieselbe Rechnung über alle Wörter.
	var falsch: Array = []
	for w in c.ablehnen:
		var rest := str(w)
		for a in c.ablehnen:
			rest = rest.replace(str(a), " ")
		for n in c.nie:
			if rest.contains(str(n)):
				falsch.append(w)
	check(falsch.is_empty(), "jedes Ablehnen-Wort bleibt ohne seine Ablehnen-Teile frei von Akzeptieren-Wörtern %s" % str(falsch))
	check(c.ablehnen.has("nur notwendige") and c.nie.has("akzeptieren") and c.nie.has("accept"), "Wortlisten vollständig")


func _skript() -> void:
	print("Filter-Skript")
	var js := FileAccess.get_file_as_string("res://helper/uzai-browser-filter.js")
	check(js.length() > 2000, "Skript da")
	for bad in ["eval(", "new Function", "Function(", "innerHTML", "outerHTML", "insertAdjacentHTML", "document.write", "fetch(", "XMLHttpRequest", "WebSocket",
			"postMessage", "chrome.webview", "sendBeacon", "localStorage", "sessionStorage", "indexedDB", "document.cookie", "window.open", "submit(", "setTimeout(\""]:
		check(not js.contains(bad), "kein %s" % bad)
	check(js.contains("window.top !== window") and js.contains("__uzaiMeldung") and js.contains("display:none!important"), "nur Hauptrahmen, eigene Bindung, nur Verstecken")
	check(js.contains("var rest = ohne(t, regeln.ablehnen);") and js.contains("rest !== null && !enthaelt(rest, regeln.nie)"),
		"Knopf nur mit Ablehnen-Wort und ohne Akzeptieren-Wort (Ablehnen-Teile vorher heraus)")
	var karte := FileAccess.get_file_as_string("res://helper/uzai-browser-karte.js")
	check(karte.contains("case 'filter': { var fl = globalThis.__uzaiFilter;"), "Sprung-Skript reicht Filter-Befehle weiter")

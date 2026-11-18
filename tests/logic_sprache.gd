extends Node
## Übersetzungen (Punkte 8, 54): genau, Muster mit Platzhaltern, Bruchstücke, Namen bleiben,
## andere Reihenfolge, der englische Katalog passt zu den Platzhaltern im Deutschen.
## Aufruf: godot --headless --path . res://tests/logic_sprache.tscn

const Lang := preload("res://src/core/lang.gd")
const RemoteS := preload("res://src/core/remote.gd")
const TwitchP := preload("res://src/core/twitch_parse.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	var t = Lang.new()
	t.load_dict({
		"Einstellungen": "Settings",
		"Filme": "Movies",
		"Läuft: %s": "Playing: %s",
		"%d neue Videos": "%d new videos",
		"Sicherung vom %s um %s": "Backup at {1} from {0}",
		"%.1f GB frei": "%.1f GB free",
		" ist live in deinem Sprachkanal.": " is live in your voice channel.",
		"Zu 100 % sicher": "100 % sure",
		"zuletzt %s": "last played %s",
		"vor %d Tagen": "%d days ago",
		"Titel#1": "track",
		"Titel#n": "tracks",
		"Titel": "Title",
		"Okt.": "Oct",
		"Oktober": "October",
		"@tag_monat": "{1} {0}",
		"@datum": "{1} {0}, {2}",
		"an ": "to ",
		" und ": " and ",
		"Läuft: ": "Playing: ",
		"Zuletzt online ": "Last online ",
		"vor %d Std.": "%d hrs ago",
		"noch %d Min.": "%d min left",
		"Weiterschauen": "Continue watching",
		"%s: %s": "%s: %s",
		" und dann weiter mit ": " and then on to ",
		"%s von %s": "%s of %s",
		"%s Std.": "%s hrs",
		"Freigeschaltet am %s": "Unlocked on %s",
		"An Uzai senden": "Send to Uzai",
		"am %s": "on %s",
		"am Stück gespielt – im Schnitt %s pro Runde.": "played in a row – %s per session on average.",
	})
	print("Übersetzen")
	check(t.translate("Einstellungen") == "Settings", "genau")
	check(t.translate("Läuft: Bohemian Rhapsody") == "Playing: Bohemian Rhapsody", "Muster, der Titel bleibt")
	check(t.translate("Läuft: Filme") == "Playing: Movies", "eingesetzte Bereichsnamen werden mitübersetzt")
	check(t.translate("12 neue Videos") == "12 new videos", "Zahl im Muster")
	check(t.translate("Sicherung vom 22.10.2026 um 08:40") == "Backup at 08:40 from 22.10.2026", "andere Reihenfolge mit {0} {1}")
	check(t.translate("3,5 GB frei") == "3,5 GB free" and t.translate("3.5 GB frei") == "3.5 GB free", "Kommazahl")
	check(t.translate("Anna ist live in deinem Sprachkanal.") == "Anna is live in your voice channel.", "angehängtes Bruchstück")
	check(t.translate("Zu 100 % sicher") == "100 % sure", "Prozentzeichen ist kein Platzhalter")
	check(t.translate("Die Siedler") == "Die Siedler" and t.translate("Okami HD") == "Okami HD", "Unbekanntes (Spielnamen) bleibt")
	check(str(t._get_message(&"Einstellungen", &"")) == "Settings" and t._cache.has("Einstellungen"), "über Godot, gemerkt")
	check(t.translate("zuletzt vor 3 Tagen") == "last played 3 days ago", "eingesetzter Teil ist selbst ein Muster")
	check(t.translate("zuletzt Elden Ring") == "last played Elden Ring", "eingesetzter Name bleibt")
	check(t.translate("Batman Arkham") == "Batman Arkham" and t.translate("Ratchet und Clank") == "Ratchet und Clank", "kurze Bruchstücke nie mitten in Namen")
	check(t.translate("Zuletzt online vor 2 Std.") == "Last online 2 hrs ago", "Bruchstück vorn, der Rest als Muster")
	check(t.translate("Weiterschauen  ·  noch 18 Min.") == "Continue watching  ·  18 min left", "Zeile mit · Stück für Stück")
	check(t.translate("A und dann weiter mit B") == "A and then on to B", "langes Bruchstück mitten im Text")
	check(t.translate("Weiterschauen: Filme") == "Continue watching: Movies", "Gliederungsmuster übersetzt die Teile")
	check(t.translate("3 von 5") == "3 of 5" and t.translate("Die Geschichte von Zelda") == "Die Geschichte von Zelda",
			"kurzes Wort zwischen Platzhaltern nur mit Zahl")
	check(t.translate("Zuletzt online vor 2 Std.") == "Last online 2 hrs ago", "Bruchstück vorn vor Muster, das mit Platzhalter beginnt")
	check(t.translate("Freigeschaltet am 3.10.  ·  3 von 5") == "Unlocked on 3.10.  ·  3 of 5", "Platzhalter verschluckt keinen Trenner")
	check(TranslationServer.translate("%s von %s") == "%s von %s" and t.translate("%s von %s") == "%s of %s", "Vorlage selbst übersetzbar")
	check(t.translate("am Stück gespielt – im Schnitt 12 Min. pro Runde.") == "played in a row – 12 Min. per session on average."
			and t.translate("am 3.10.") == "on 3.10.", "genaueres Muster vor kurzem mit gleichem Anfang")
	check(t.translate("Einstellungen\n\nLäuft: Filme\nzuletzt vor 3 Tagen") == "Settings\n\nPlaying: Movies\nlast played 3 days ago",
			"mehrere Absätze Zeile für Zeile")
	var lang_long := "Einstellungen\n" + "x".repeat(700)
	check(t.translate(lang_long) == "Settings\n" + "x".repeat(700) and t.translate("y".repeat(700)) == "y".repeat(700), "langer Text nur zeilenweise")
	print("Mehrzahl und Datum (eingestellte Sprache)")
	t.locale = "en"
	TranslationServer.add_translation(t)
	TranslationServer.set_locale("en")
	check(Lang.count(1, "Titel", "Titel") == "1 track" and Lang.count(3, "Titel", "Titel") == "3 tracks", "Einzahl und Mehrzahl, im Deutschen gleich")
	check(TranslationServer.translate("Titel") == "Title", "ohne Kontext die Überschrift")
	check(Lang.count(2, "Spiel", "Spiele") == "2 Spiele", "ohne Eintrag bleibt das Wort")
	check(Lang.date_text(22, 10) == "October 22", "Tag und Monat")
	check(Lang.date_text(2, 10, 2026, false, true) == "Oct 2, 2026", "Datum eindeutig, ohne Zahlenreihenfolge")
	check(RemoteS.form_html({ "title": "Einstellungen", "hint": "" }).contains("Send to Uzai")
			and RemoteS.form_html({ "title": "Einstellungen", "hint": "" }).contains("Settings"), "Handy-Seite in der Sprache von Uzai")
	TranslationServer.remove_translation(t)
	TranslationServer.set_locale("de")
	check(Lang.date_text(2, 10, 2026, false, true) == "02.10.2026" and Lang.date_text(22, 10) == "22. Oktober", "Deutsch ohne Katalog")
	check(Lang.month_year(3, 2019) == "März 2019", "Monat und Jahr")
	print("Katalog")
	var path := "res://i18n/en.json"
	var cat: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	check(cat is Dictionary and (cat as Dictionary).size() > 0, "i18n/en.json lesbar")
	if cat is Dictionary:
		var bad: Array = []
		for k in cat:
			if _slots(str(k)) != _slots(str(cat[k])) and not str(cat[k]).contains("{0}"):
				bad.append(k)
		check(bad.is_empty(), "gleiche Platzhalter in Deutsch und Englisch (%d abweichend: %s)" % [bad.size(), str(bad.slice(0, 5))])
		var empty := (cat as Dictionary).keys().filter(func(k: Variant) -> bool: return str(cat[k]).strip_edges() == "")
		check(empty.is_empty(), "keine leeren Übersetzungen (%d)" % empty.size())
	print("Zahlen mit Tausendertrennung")
	check(Lang.tausender(41237) == "41.237" and Lang.tausender(999) == "999" and Lang.tausender(1000) == "1.000" and Lang.tausender(0) == "0"
			and Lang.tausender(-1234567) == "-1.234.567" and Lang.tausender(-123) == "-123", "Deutsch: Punkt; kleine und negative Zahlen stimmen")
	check(TwitchP.viewers_text(4200) == "4.200 Zuschauer" and TwitchP.count_text(1234567) == "1.234.567", "Zuschauerzahl auf Deutsch wie bisher")
	Lang.apply("en")
	check(Lang.tausender(41237) == "41,237" and Lang.tausender(999) == "999" and Lang.dec("3.5 GB") == "3.5 GB",
			"Englisch: Komma als Tausenderzeichen, Punkt bleibt das Komma (%s)" % Lang.tausender(41237))
	var zuschauer := str(TranslationServer.translate(TwitchP.viewers_text(4200)))
	check(zuschauer == "4,200 viewers", "Englisch: Zuschauerzahl über den Katalog (%s)" % zuschauer)
	Lang.release()
	TranslationServer.set_locale("de")
	check(Lang.tausender(41237) == "41.237", "zurück auf Deutsch: wieder der Punkt")

	print("Land für Preise und Angebote")
	check(Lang.land_fuer("auto", "de", "de_DE") == "DE" and Lang.land_fuer("auto", "de", "en_US") == "DE" and Lang.land_fuer("auto", "de", "") == "DE",
			"Deutsch gewählt: Deutschland – auch auf einem englischen Windows")
	check(Lang.land_fuer("auto", "de", "de_AT") == "AT" and Lang.land_fuer("auto", "de", "de-CH") == "CH", "Deutsch in Österreich und der Schweiz: das eigene Land")
	check(Lang.land_fuer("auto", "en", "en_GB") == "GB" and Lang.land_fuer("auto", "en_US", "en_US") == "US" and Lang.land_fuer("auto", "en", "en-AU") == "AU",
			"Englisch gewählt: das Land, das Windows nennt")
	check(Lang.land_fuer("auto", "en", "de_DE") == "DE" and Lang.land_fuer("auto", "en", "fr_FR.UTF-8") == "FR", "Englisch auf einem deutschen oder französischen Windows: dessen Land")
	check(Lang.land_fuer("auto", "en", "en") == "US" and Lang.land_fuer("auto", "en", "") == "US" and Lang.land_fuer("auto", "en", "C") == "US", "Englisch ohne Landesangabe: USA")
	check(Lang.land_fuer("AT", "de", "de_DE") == "AT" and Lang.land_fuer("gb", "de", "de_DE") == "GB" and Lang.land_fuer(" us ", "en", "en_GB") == "US",
			"eigene Wahl geht vor (auch klein geschrieben)")
	check(Lang.land_fuer("Deutschland", "en", "en_GB") == "GB" and Lang.land_fuer("D1", "de", "") == "DE" and Lang.land_fuer("", "de", "") == "DE", "Unsinn als Wahl: wie automatisch")
	check(Lang.land_aus("zh_Hans_CN") == "CN" and Lang.land_aus("en_gb") == "GB" and Lang.land_aus("de") == "" and Lang.land_aus("sr_Latn") == ""
			and Lang.land_aus("de_DE@euro") == "DE",
			"Land aus der Kennung: auch mit Schrift, klein geschrieben, mit Zusatz; ohne Land leer")
	for l in Lang.LAENDER:
		check(Lang.land_fuer(str(l[0]), "de", "") == str(l[0]) and Lang.ZEITZONE.has(str(l[0])), "Land %s: wählbar, Zeitzone bekannt" % str(l[0]))
	check(Lang.waehrung_fuer("DE") == "EUR" and Lang.waehrung_fuer("AT") == "EUR" and Lang.waehrung_fuer("US") == "USD" and Lang.waehrung_fuer("gb") == "GBP"
			and Lang.waehrung_fuer("CH") == "CHF" and Lang.waehrung_fuer("XX") == "EUR", "Währung je Land, unbekannt: Euro")
	check(Lang.betrag(1249, "EUR") == "12,49 €" and Lang.betrag(5, "EUR") == "0,05 €" and Lang.betrag(1249, "USD") == "12,49 $" and Lang.betrag(1249, "CHF") == "12,49 CHF",
			"Betrag auf Deutsch: Komma, Zeichen dahinter (%s)" % Lang.betrag(1249, "CHF"))
	TranslationServer.set_locale("en")
	check(Lang.betrag(1249, "USD") == "$12.49" and Lang.betrag(1249, "GBP") == "£12.49" and Lang.betrag(1249, "EUR") == "€12.49" and Lang.betrag(5, "USD") == "$0.05",
			"Betrag auf Englisch: Zeichen davor, Punkt")
	check(Lang.betrag(1249, "CHF") == "CHF 12.49" and Lang.betrag(1249, "SEK") == "SEK 12.49", "Währung ohne Zeichen: Kürzel davor")
	TranslationServer.set_locale("de")
	var keep_land: Variant = Config.get_value("system.country", "auto")
	Config.set_value("system.country", "auto")
	check(Config.land() == "DE" and Config.waehrung() == "EUR", "Standard hier (Deutsch): Deutschland, Euro")
	Config.set_value("system.country", "US")
	check(Config.land() == "US" and Config.waehrung() == "USD", "Einstellung „USA“: US, Dollar")
	Config.set_value("system.country", keep_land)

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Platzhalter der Reihe nach (%s, %d, %.1f …), ohne %%.
static func _slots(s: String) -> Array:
	var out: Array = []
	var i := 0
	while i < s.length():
		if s[i] == "%":
			var j := Lang._slot_end(s, i)
			if j > i:
				out.append(s.substr(i, j - i))
				i = j
				continue
		i += 1
	return out

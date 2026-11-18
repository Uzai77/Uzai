extends Node
## ScreenScraper (src/core/screenscraper.gd) ohne Netz: Zugangsdaten nur, wo sie hingehören (nie in
## gemerkten Adressen, nie im Protokoll), Bilder nur von screenscraper.fr per https, Antworten streng
## geprüft, Regionen nach Sprache, Ablehnungen richtig gedeutet; dazu die Einbindung in Media, die
## Kandidaten der Bildwahl je Spiel (Beispielantwort tests/fixtures/screenscraper), die Wahl der Quelle
## und der Weg „Alles ersetzen“ mit Ersatz-Quellen (ohne Netz); PC-Spiele (Steam & Co.): System
## PC Windows 138 / PC Dos 135, Namenssuche, Bestwahl nach Name und Jahr, Grenzen aus ssuser
## (nachgebaute Antworten, tests/fixtures/screenscraper/jeuRecherche_pc.json).
## Aufruf: godot --headless --path . res://tests/logic_screenscraper.tscn

const SS := preload("res://src/core/screenscraper.gd")
const MD := preload("res://src/core/media_daten.gd")
const SpieleScrapen := preload("res://src/ui/layers/spiele_scrapen.gd")
const ArtPicker := preload("res://src/ui/layers/art_picker.gd")
const GameProfile := preload("res://src/core/game_profile.gd")
const FIX := "res://tests/fixtures/screenscraper/"

const Z := { "devid": "uzaidev", "devpassword": "geheim123", "ssid": "jemand", "sspassword": "pw&x" }

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_zugang()
	_adressen()
	_antwort()
	_einbindung()
	_kandidaten()
	_suche()
	_quellwahl()
	_pc()
	await _pc_media()
	await _ersetzen()
	await _pc_ersetzen()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _zugang() -> void:
	print("Zugangsdaten")
	check(SS.dev_aus("{\"devid\": \"a\", \"devpassword\": \"b\"}") == { "devid": "a", "devpassword": "b" }, "Datei mit beiden Werten")
	check(SS.dev_aus("") == {} and SS.dev_aus("[1]") == {} and SS.dev_aus("{\"devid\": \"a\"}") == {}, "leer, falsch oder halb: kein Zugang")
	check(SS.dev_aus("{\"devid\": \"a b\", \"devpassword\": \"c\"}") == {} and SS.dev_aus("x".repeat(5000)) == {}, "Leerzeichen oder riesig: kein Zugang")
	check(SS.wert_ok("abc_123") and not SS.wert_ok("") and not SS.wert_ok("a\nb") and not SS.wert_ok("x".repeat(65)), "wert_ok: sichtbar, kurz, ohne Umbruch")


func _adressen() -> void:
	print("Adressen")
	var g := { "system": "ps2", "path": "C:/Spiele/PS2/Okami (Europe).iso", "title": "Okami" }
	var u := SS.anfrage(g, 4500000000, Z)
	check(u.begins_with(SS.API) and u.contains("systemeid=58") and u.contains("romtaille=4500000000"), "Anfrage: System und Größe")
	check(u.contains("romnom=" + "Okami (Europe).iso".uri_encode()) and not u.contains("C:"), "nur der Dateiname, nie der Pfad")
	check(u.contains("sspassword=" + "pw&x".uri_encode()) and not u.contains("pw&x"), "Zugangsdaten kodiert (kein & bricht die Abfrage)")
	check(SS.anfrage({ "system": "pc", "path": "x.exe" }, 1, Z) == "" and SS.anfrage(g, 1, {}) == "", "unbekanntes System oder ohne Zugang: keine Anfrage")
	check(not SS.anfrage(g, -1, Z).contains("romtaille"), "Größe unbekannt: weggelassen")
	var bild := "https://neoclone.screenscraper.fr/api2/mediaJeu.php?devid=uzaidev&devpassword=geheim123&softname=Uzai&ssid=jemand&sspassword=x&systemeid=58&jeuid=1&media=box-2D(eu)"
	var ohne := SS.ohne_zugang(bild)
	check(not ohne.contains("geheim123") and not ohne.contains("devid=") and not ohne.contains("ssid=") and ohne.contains("jeuid=1") and ohne.contains("media=box-2D(eu)"),
			"gemerkte Adresse ohne Zugangsdaten, der Rest bleibt")
	var mit := SS.mit_zugang(ohne, Z)
	check(mit.contains("devpassword=geheim123") and mit.contains("jeuid=1"), "beim Laden kommen sie wieder dazu")
	check(SS.bild_ok("https://www.screenscraper.fr/x.png") and SS.bild_ok("https://screenscraper.fr/a"), "screenscraper.fr und Unterdomänen")
	check(not SS.bild_ok("http://neoclone.screenscraper.fr/a") and not SS.bild_ok("https://screenscraper.fr.evil.example/a")
			and not SS.bild_ok("https://evilscreenscraper.fr/a") and not SS.bild_ok("https://user@screenscraper.fr/a")
			and not SS.bild_ok("https://screenscraper.fr:8443/a") and not SS.bild_ok("https://x.screenscraper.fr\\@evil/a"),
			"kein http, keine fremden oder ähnlichen Hosts, keine Anmeldung oder Ports")
	check(SS.ohne_zugang("https://evil.example/a?devid=1") == "" and SS.mit_zugang("https://evil.example/a", Z) == "", "fremde Adresse bekommt nie Zugangsdaten")


func _antwort() -> void:
	print("Antwort")
	var d := { "response": { "jeu": { "id": "3017", "noms": [{ "region": "jp", "text": "Ōkami JP" }, { "region": "eu", "text": "Okami" }],
		"medias": [
			{ "type": "box-2D", "region": "us", "format": "png", "url": "https://neoclone.screenscraper.fr/m?devid=a&jeuid=3017&media=box-2D(us)" },
			{ "type": "box-2D", "region": "eu", "format": "png", "url": "https://neoclone.screenscraper.fr/m?devid=a&jeuid=3017&media=box-2D(eu)" },
			{ "type": "box-2D", "region": "de", "format": "png", "url": "https://evil.example/m?media=box-2D(de)" },
			{ "type": "fanart", "format": "jpg", "url": "https://neoclone.screenscraper.fr/m?jeuid=3017&media=fanart" },
			{ "type": "wheel", "region": "wor", "format": "svg", "url": "https://neoclone.screenscraper.fr/m?media=wheel" },
			{ "type": "wheel-hd", "region": "wor", "format": "png", "url": "https://neoclone.screenscraper.fr/m?media=wheel-hd" },
			"kaputt", 42 ] } } }
	var r := SS.lesen(d, "de")
	check(bool(r.ok) and str(r.id) == "3017" and str(r.name) == "Okami", "Kennung und Name (Region nach Sprache)")
	check(str(r.medien.cover.url).contains("box-2D(eu)") and not str(r.medien.cover.url).contains("devid"), "Cover: beste erlaubte Region, fremder Host übergangen, ohne Zugang")
	check(str(r.medien.hero.fmt) == "jpg" and str(r.medien.logo.url).contains("wheel-hd"), "Hintergrund aus fanart, Schriftzug als PNG (SVG nicht)")
	check(str(SS.lesen(d, "en").medien.cover.url).contains("box-2D(us)"), "Englisch: zuerst US")
	check(not bool(SS.lesen(null).ok) and not bool(SS.lesen({ "response": { "jeu": [] } }).ok) and not bool(SS.lesen({ "response": { "jeu": { "id": "x;rm" } } }).ok),
			"falsche Typen oder Kennung: nichts")
	var viele: Array = []
	for i in 5000:
		viele.append({ "type": "ss", "format": "png", "url": "https://screenscraper.fr/%d" % i })
	var t0 := Time.get_ticks_usec()
	SS.lesen({ "response": { "jeu": { "id": "1", "medias": viele } } })
	check(Time.get_ticks_usec() - t0 < 200000, "riesige Medienliste: gedeckelt, schnell")
	check(SS.fehler(401) == "zugang" and SS.fehler(404) == "fehlt" and SS.fehler(430) == "kontingent" and SS.fehler(431) == "kontingent"
			and SS.fehler(426) == "zu" and SS.fehler(500) == "netz", "Ablehnungen gedeutet")


func _einbindung() -> void:
	print("Einbindung in Media")
	var rom := { "source": "rom", "system": "ps2" }
	var q := MD.remote_sources(rom, "cover", { "sgdb": true, "ss": true, "libretro": true })
	check(q.find("sgdb") < q.find("ss") and q.find("ss") < q.find("libretro") and q.find("ss") >= 0, "Reihenfolge: SteamGridDB, ScreenScraper, Libretro")
	var steam := { "source": "steam", "appid": "1" }
	check(not MD.remote_sources(rom, "cover", { "ss": false }).has("ss") and not MD.remote_sources(steam, "cover", { "ss": true }).has("ss")
			and not MD.remote_sources(rom, "icon", { "ss": true }).has("ss"),
			"automatisch: nur eingeschaltet, nur Emulator-Spiele (PC: bisherige Quellen), nur Cover/Hintergrund/Schriftzug")
	var me := FileAccess.get_file_as_string("res://src/core/media.gd")
	var fs := me.substr(me.find("func _from_ss("), 1200)
	check(not fs.contains("note_url") and fs.contains("mit_zugang"), "ScreenScraper-Adressen nie als öffentliche Adresse gemerkt (Discord-Status)")
	var si := me.substr(me.find("func _ss_fragen("), 2000)
	check(si.contains("log_line(\"scrape\"") and not si.substr(si.find("log_line(\"scrape\""), 220).contains("url") and si.contains("Screenscraper.sauber("),
			"Protokoll ohne Adresse, Text bereinigt")
	check(FileAccess.get_file_as_string("res://.gitignore").contains("data/screenscraper_dev.json"), "Programmzugang nie im Repo")
	var vault := FileAccess.get_file_as_string("res://src/core/vault.gd")
	check(vault.contains("\"accounts.ss_pass\"") and vault.contains("\"accounts.ss_devpass\""), "Passwörter im Tresor")
	# Spiele scrapen: in der Einrichtung einmal von selbst, sonst sichtbar in Bibliothek und „Für dich“.
	var SW: GDScript = load("res://src/ui/layers/setup_wizard_spiele.gd")
	check(SW.scrape_auto_ok(false, 5, false, 1) and not SW.scrape_auto_ok(true, 5, false, 1), "Einrichtung scrapt einmal von selbst")
	check(not SW.scrape_auto_ok(false, 0, false, 1) and not SW.scrape_auto_ok(false, 5, true, 1) and not SW.scrape_auto_ok(false, 5, false, 0),
		"nicht ohne fehlende Cover, nicht doppelt, nicht ohne Quelle")
	# The "Spiele scrapen" status also counts covers that already arrived during the import; before, the first run
	# showed nothing about them.
	check(SW.scrape_stand(false, 16, 4) == "12 von 16 mit Cover" and SW.scrape_stand(false, 16, 0) == "Alle da"
			and SW.scrape_stand(true, 16, 16) == "Läuft …" and SW.scrape_stand(false, 16, 16) == "0 von 16 mit Cover",
			"Einrichtung: Stand zeigt, wie viele schon ein Cover haben")
	var sws := FileAccess.get_file_as_string("res://src/ui/layers/setup_wizard_spiele.gd")
	var tick := sws.substr(sws.find("func _spiele_tick("), sws.find("static func spiele_leer(") - sws.find("func _spiele_tick("))
	check(tick.contains("_scrape_r.set(\"value_text\", stand)") and sws.contains("_scrape_r = r"), "Einrichtung: Stand läuft mit, solange Cover kommen")
	check(FileAccess.get_file_as_string("res://src/ui/layers/library_grid.gd").contains("lib:scrapen"), "Bibliothek: Spiele scrapen")
	var fd := FileAccess.get_file_as_string("res://src/ui/layers/fuer_dich_leiste.gd")
	check(fd.contains("\"Spiele scrapen\"") and not fd.contains("if fehlt <= 0 or main == null"), "Für dich: Spiele scrapen auch ohne fehlende Cover")


func _fixture(name: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(FIX + name))


func _kandidaten() -> void:
	print("Kandidaten (Bildwahl je Spiel)")
	var d: Variant = _fixture("jeuInfos.json")
	var r := SS.lesen(d, "de")
	check(bool(r.ok) and str(r.name) == "Okami" and int(r.system) == 58, "Beispielantwort gelesen: Name nach Region, System")
	var k: Dictionary = r.kandidaten
	var cover: Array = k.get("cover", [])
	check(cover.size() == 4, "Cover: box-2D us/eu/jp + box-3D (doppelte, fremder Host, zu groß: raus) – %d" % cover.size())
	check(not cover.is_empty() and str(cover[0].region) == "eu" and str(cover[0].typ) == "box-2D" and str(cover[cover.size() - 1].typ) == "box-3D",
			"Reihenfolge: box-2D nach Region (Deutsch: EU zuerst), dann 3D")
	var alle := JSON.stringify(k)
	check(not alle.contains("GEHEIM") and not alle.contains("devid") and not alle.contains("evil"), "keine Zugangsdaten, kein fremder Host")
	var hero: Array = k.get("hero", [])
	check(hero.size() == 2 and str(hero[0].typ) == "fanart" and str(hero[1].typ) == "ss", "Hintergrund: Fanart, Szene (http-Titelbild raus)")
	var logo: Array = k.get("logo", [])
	check(logo.size() == 2 and str(logo[0].typ) == "wheel-hd" and not alle.contains("svg"), "Logo: HD, Carbon – kein SVG")
	check((k.get("ruecken", []) as Array).size() == 1 and not alle.contains("manuel") and not alle.contains("video"), "Rücken da; Handbuch und Video nicht")
	check(SS.kandidaten_pruefen(JSON.parse_string(JSON.stringify(k))) == k, "gemerkt und wieder gelesen: unverändert")
	var falsch := k.duplicate(true)
	(falsch.cover as Array).append({ "url": "https://evil.example/x.png", "fmt": "png", "typ": "box-2D", "region": "eu" })
	(falsch.cover as Array).append({ "url": "https://neoclone.screenscraper.fr/m?devpassword=x", "fmt": "png", "typ": "box-2D", "region": "eu" })
	(falsch.cover as Array).append({ "url": str(cover[0].url), "fmt": "exe", "typ": "box-2D", "region": "eu" })
	falsch["boese"] = [{ "url": str(cover[0].url) }]
	check(SS.kandidaten_pruefen(falsch) == k and SS.kandidaten_pruefen("x") == {} and SS.kandidaten_pruefen({ "cover": "x" }) == {},
			"Cache-Datei verfälscht: fremde Hosts, Zugangsdaten, Formate, Arten fallen raus")
	var v := SS.vorschau(str(cover[0].url), 240)
	check(v.ends_with("&maxwidth=240") and SS.vorschau("https://evil.example/a.png", 240) == "" and SS.vorschau(str(cover[0].url), 99999).ends_with("=1200"),
			"Vorschau klein von ScreenScraper, nie fremd")
	var kz := SS.kontingent(d)
	check(int(kz.heute) == 120 and int(kz.max) == 20000 and not SS.kontingent_voll(kz), "Kontingent gelesen, noch nicht voll")
	check(SS.kontingent_voll(SS.kontingent(_fixture("jeuRecherche.json"))) and SS.kontingent(null).max == -1, "Kontingent voll erkannt; ohne Angabe: unbekannt")
	check(ArtPicker.ss_etikett(cover[0]) == "EU" and ArtPicker.ss_etikett(cover[cover.size() - 1]) == "EU · 3D" and ArtPicker.ss_etikett(hero[1]) == "EU · Szene",
			"Schild auf der Kachel: Region und Variante")
	check(ArtPicker.ss_fehler("kontingent").contains("Tageslimit") and ArtPicker.ss_fehler("zugang").contains("Zugang")
			and ArtPicker.ss_fehler("fehlt").contains("Anderes Spiel"),
			"Bildwahl sagt, warum nichts kommt")


func _suche() -> void:
	print("Suche, Anfragen, Fehler")
	var t := SS.suche_lesen(_fixture("jeuRecherche.json"), "de")
	check(t.size() == 3, "Treffer gelesen, kaputte und leere fallen weg (%d)" % t.size())
	var b := SS.bester_treffer(t, "Okami (Europe)", "ps2")
	check(str(b.get("id", "")) == "3017", "bester Treffer: gleiches System, gleicher Name")
	check(SS.bester_treffer(t, "Final Fantasy X", "ps2").is_empty() and SS.bester_treffer(t, "Okami", "n64").is_empty(), "anderer Name oder System: keiner")
	var g := { "system": "ps2", "path": "C:/Spiele/PS2/Okami (Europe).chd", "title": "Okami" }
	var u := SS.anfrage(g, 1000, Z, "0123456789abcdef0123456789ABCDEF")
	check(u.contains("romtype=iso") and u.contains("md5=0123456789abcdef0123456789abcdef"), "Disc-Abbild als iso, Prüfsumme dabei")
	check(not SS.anfrage(g, 1000, Z, "zu kurz").contains("md5=") and SS.anfrage({ "system": "snes", "path": "a.sfc" }, 1, Z).contains("romtype=rom"), "falsche Prüfsumme weg; ROM als rom")
	check(SS.anfrage_id("3017", "ps2", Z).contains("gameid=3017") and SS.anfrage_id("1;x", "ps2", Z) == "" and SS.anfrage_id("3017", "pc", Z) == "", "Anfrage nach Kennung, nur gültig")
	var s := SS.anfrage_suche("Okami (Europe) & Co/../x", "ps2", Z)
	check(s.begins_with(SS.SUCHE_API) and s.contains("recherche=okami%20co%20x") and not s.contains("..") and not s.contains("%2F"),
			"Suche: nur ein sauberer Name geht hinaus")
	check(SS.md5_sinnvoll("a.sfc", 4 * 1024 * 1024) and not SS.md5_sinnvoll("a.zip", 1000) and not SS.md5_sinnvoll("a.iso", 4 * 1024 * 1024 * 1024), "Prüfsumme nur für kleine Dateien ohne Archiv")
	check(SS.fehler(200, "Erreur de login : Vérifier vos identifiants développeur !") == "zugang" and SS.fehler(200, "Votre quota de scrape est dépassé") == "kontingent"
			and SS.fehler(0, "") == "netz" and SS.fehler(400) == "fehlt", "Ablehnungen auch aus dem Text gedeutet")
	var sauber := SS.sauber("Fehler geheim123 bei https://api.screenscraper.fr/api2/x?devpassword=geheim123\nzweite", Z)
	check(not sauber.contains("geheim123") and not sauber.contains("https") and not sauber.contains("\n"), "Protokolltext: ohne Passwort, ohne Adresse, einzeilig")
	check(SS.grund_text("zugang") == "Zugang abgelehnt" and SS.grund_text("kontingent") == "Tageslimit erreicht", "Gründe in kurzen Worten")


func _quellwahl() -> void:
	print("Wahl der Quelle")
	check(MD.quellen_pruefen(["sgdb"]) == ["sgdb"] and MD.quellen_pruefen(["sgdb", "ss"]) == ["sgdb", "ss"], "Wahl: eine oder beide in Reihenfolge")
	check(MD.quellen_pruefen(null) == ["ss", "sgdb"] and MD.quellen_pruefen(["ss", "ss"]) == ["ss", "sgdb"] and MD.quellen_pruefen(["x"]) == ["ss", "sgdb"]
			and MD.quellen_pruefen("ss") == ["ss", "sgdb"] and MD.quellen_pruefen([1]) == ["ss", "sgdb"], "Unsinn in der Config: Vorgabe (ScreenScraper zuerst)")
	var alt: Variant = Config.get_value("library.scrape_quellen", null)
	Config.set_value("library.scrape_quellen", ["sgdb"])
	check(Media.scrape_wahl_roh() == ["sgdb"], "Wahl gemerkt (Config)")
	Config.set_value("library.scrape_quellen", alt)
	check(Media.quelle_kann("sgdb", "icon") and not Media.quelle_kann("ss", "icon") and Media.quelle_kann("ss", "ruecken") and not Media.quelle_kann("sgdb", "ruecken"),
			"Symbol nur SteamGridDB, Rücken nur ScreenScraper")
	check(SpieleScrapen.wahl_text(["ss"], false).contains("ScreenScraper.fr") and SpieleScrapen.wahl_text(["sgdb", "ss"], true).begins_with("Erst SteamGridDB")
			and SpieleScrapen.wahl_text(["ss", "sgdb"], false).contains("Schlüssel") and SpieleScrapen.wahl_text(["sgdb"], false).contains("Schlüssel"),
			"Text zur Wahl: Quellenangabe, Reihenfolge, Hinweis auf den Schlüssel")
	var src := FileAccess.get_file_as_string("res://src/ui/layers/spiele_scrapen.gd")
	check(src.contains("\"scrapen:quelle:\"") and src.contains("Reihenfolge tauschen") and src.contains("SetupKonten.open_sgdb(main)"), "Menü: Wahl mit Controller, Tauschen, Weg zum Schlüssel")
	var go := FileAccess.get_file_as_string("res://src/ui/layers/game_options.gd")
	check(go.contains("\"Von ScreenScraper\"") and go.contains("Media.ss_bildwahl_ok(game)"), "Je Spiel: ScreenScraper in der Bildwahl")
	check(not Media.ss_bildwahl_ok({ "source": "rom", "system": "pc" }) and not Media.ss_bildwahl_ok({ "source": "app", "system": "pc" }),
			"nicht für unbekannte Systeme oder Apps")
	var ok := Media.scrape_leer(["ss", "sgdb"])
	ok.images = 5
	ok.quellen.ss.geholt = 4
	ok.quellen.sgdb.geholt = 1
	var m := Media.scrape_meldung(ok)
	check(str(m[0]) == "Bilder geholt: 5 neu" and str(m[1]) == "ScreenScraper: 4 · SteamGridDB: 1" and not Media.scrape_problem(ok), "Mitteilung: je Quelle, wie viele")
	var schlecht := Media.scrape_leer(["ss", "sgdb"])
	schlecht.quellen.ss.grund = { "fehlt": 3, "zugang": 1 }
	schlecht.quellen.sgdb.grund = { "kontingent": 2 }
	schlecht.failed = 3
	m = Media.scrape_meldung(schlecht)
	check(str(m[0]) == "Keine neuen Bilder" and str(m[1]).contains("ScreenScraper: Zugang abgelehnt") and str(m[1]).contains("SteamGridDB: Limit erreicht")
			and str(m[1]).contains("3 Spiele ohne Treffer") and Media.scrape_problem(schlecht), "Mitteilung: ehrlich, warum nichts kam")
	var gleich := Media.scrape_leer(["ss"])
	gleich.quellen.ss.gleich = 7
	gleich.eigen = 2
	m = Media.scrape_meldung(gleich)
	check(str(m[1]) == "ScreenScraper: schon aktuell · 2 eigene behalten", "Mitteilung: schon aktuell, eigene behalten (%s)" % str(m[1]))
	var nix := Media.scrape_leer(["ss"])
	nix.quellen.ss.grund = { "fehlt": 4 }
	check(str(Media.scrape_meldung(nix)[1]) == "ScreenScraper: nicht gefunden", "Mitteilung: nicht gefunden")


## Alles ersetzen mit Ersatz-Quellen: Vorhandenes (Libretro-Scan, alter Cache, Medienordner) wird
## wirklich ersetzt, mit neuem Pfad; selbst Gewähltes bleibt; gleiche Bilder zählen als aktuell.
func _ersetzen() -> void:
	print("Alles ersetzen")
	var dir := Config.path("cache/img")
	DirAccess.make_dir_recursive_absolute(dir.path_join("ss"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("libretro"))
	var png := FileAccess.get_file_as_bytes("res://icon.png") if FileAccess.file_exists("res://icon.png") else PackedByteArray([0x89, 0x50, 0x4E, 0x47])
	var schreib := func(p: String) -> String:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_buffer(png)
		f.close()
		return p
	var alt_scan: String = schreib.call(dir.path_join("libretro/test_scan.png"))
	var alt_hero: String = schreib.call(dir.path_join("ss/test_hero_alt.png"))
	var eigen: String = schreib.call(Config.path("eigen_logo.png"))
	var g := { "id": "test:okami", "title": "Okami", "system": "ps2", "source": "rom",
		"images": { "logo": eigen }, "images_auto": { "cover": alt_scan, "cover_scan": alt_scan, "hero": alt_hero } }
	var geholt := {}
	var ss_fake := func(game: Dictionary, kind: String, info: Dictionary) -> String:
		check(bool(info.get("neu", false)), "Ersetzen fragt neu (%s)" % kind)
		if kind == "ruecken":
			info["grund"] = "kontingent"
			return ""
		if kind == "hero":
			return alt_hero          # dasselbe Bild wie vorher: „schon aktuell“
		var p: String = Media.bild_ziel("ss", game, kind, "https://neoclone.screenscraper.fr/m?media=%s(eu)" % kind, "png")
		geholt[kind] = p
		return schreib.call(p)
	var sgdb_fake := func(_game: Dictionary, _kind: String, info: Dictionary) -> String:
		info["grund"] = "fehlt"
		return ""
	Media.scrape_test = { "ss": ss_fake, "sgdb": sgdb_fake }
	var stand := Media.bilder_stand
	var res := Media.scrape_leer(["ss", "sgdb"])
	var box := { "running": 1 }
	await Media._scrape_one(g, ["ss", "sgdb"], true, res, box)
	Media.scrape_test = {}
	var auto: Dictionary = g.images_auto
	check(str(auto.cover) == str(geholt.get("cover", "-")) and str(auto.cover) != alt_scan, "Cover wirklich ersetzt, mit neuem Pfad")
	check(str(auto.cover_scan) == str(auto.cover), "ScreenScraper-Cover ersetzt auch den Scan fürs Regal")
	check(not FileAccess.file_exists(alt_scan), "alter Libretro-Scan aus dem Cache gelöscht")
	check(str(auto.hero) == alt_hero and FileAccess.file_exists(alt_hero) and int(res.gleich) == 1, "gleiches Bild: bleibt, zählt als aktuell")
	check(str(g.images.logo) == eigen and FileAccess.file_exists(eigen) and int(res.eigen) == 1 and not auto.has("logo"), "selbst gewähltes Logo bleibt")
	check(int(res.images) == 1 and int(res.games) == 1 and int(res.quellen.ss.geholt) == 1 and Media.bilder_stand == stand + 1, "gezählt; Bilderstand hoch (Raster, Regal, Spielseite bauen neu)")
	check(int((res.quellen.ss.grund as Dictionary).get("kontingent", 0)) == 1 and int((res.quellen.sgdb.grund as Dictionary).get("fehlt", 0)) >= 1, "Gründe je Quelle gesammelt")
	check(int(box.running) == 0, "Faden zurückgegeben")
	check(Media.local_path(g, "cover") == str(auto.cover), "Media zeigt das neue Cover")
	var a1 := Media.bild_ziel("ss", g, "cover", "https://x.screenscraper.fr/a", "png")
	check(a1 == Media.bild_ziel("ss", g, "cover", "https://x.screenscraper.fr/a", "png") and a1 != Media.bild_ziel("ss", g, "cover", "https://x.screenscraper.fr/b", "png"),
			"Dateiname je Adresse: neues Bild, neuer Pfad")
	var log := FileAccess.get_file_as_string(Config.path("logs/scrape.log"))
	check(log.contains("Okami [ps2]") and log.contains("cover ss") and log.contains("hero ss =") and not log.contains("devpassword") and not log.contains("https://"),
			"logs/scrape.log: je Spiel, was kam – ohne Adressen und Zugangsdaten")
	# Ohne Ersetzen: Vorhandenes bleibt, es wird nicht einmal gefragt.
	var gefragt := [0]
	var zaehlen := func(_g: Dictionary, _k: String, _i: Dictionary) -> String:
		gefragt[0] += 1
		return ""
	Media.scrape_test = { "ss": zaehlen }
	var res2 := Media.scrape_leer(["ss"])
	await Media._scrape_one(g, ["ss"], false, res2, { "running": 1 })
	Media.scrape_test = {}
	check(gefragt[0] == 1 and str(g.images_auto.cover) == str(auto.cover), "Fehlende holen: nur die fehlende Bildart (Rücken) gefragt")
	for p in [str(auto.cover), alt_hero, eigen]:
		DirAccess.remove_absolute(p)


## Zugang für die Proben: der Programmzugang des Pakets oder einer nur in dieser Config.
func _zugang_da() -> void:
	if not SS.zugang().has("devid"):
		Config.set_value("accounts.ss_devid", "probe")
		Config.set_value("accounts.ss_devpass", "probe")


func _pc() -> void:
	print("PC-Spiele (Steam, Epic, GOG …)")
	var steam := { "id": "steam:379720", "title": "DOOM", "source": "steam", "system": "steam", "appid": "379720", "path": "C:/Spiele/DOOM/DOOMx64vk.exe" }
	check(SS.ist_pc(steam) and SS.schluessel(steam) == "windows" and SS.nummer("windows") == 138 and SS.nummer("dos") == 135 and SS.nummer("win3x") == 136,
			"Steam-Spiel → PC Windows (systemeid 138), Dos 135, Win3.xx 136 (systemesListe)")
	check(SS.kennt(steam) and SS.kennt({ "source": "gog", "system": "gog" }) and SS.kennt({ "source": "pc", "system": "pc" })
			and not SS.kennt({ "source": "app", "system": "app" }),
			"alle PC-Quellen bekannt, Apps nicht")
	var quellen := { "steam": true }
	for q in MD.STEAM_MATCH_SOURCES:
		quellen[q] = true
	var pq := {}
	for q in SS.PC_QUELLEN:
		pq[q] = true
	check(pq.keys().size() == SS.PC_QUELLEN.size() and pq.keys().all(func(q: Variant) -> bool: return quellen.has(q))
			and quellen.keys().all(func(q: Variant) -> bool: return pq.has(q))
			and GameProfile.SOURCE_NAMES.keys().all(func(q: Variant) -> bool: return pq.has(q)), "PC-Quellen wie in Bibliothek und Spielprofil")
	check(SS.anfrage(steam, 5000, Z, "0123456789abcdef0123456789abcdef") == "" and not SS.kennt({ "source": "rom", "system": "steam" }),
			"PC: keine Anfrage über Datei oder Prüfsumme")
	var s := SS.anfrage_suche("DOOM™", SS.schluessel(steam), Z)
	check(s.begins_with(SS.SUCHE_API) and s.contains("systemeid=138") and s.contains("recherche=doom") and not s.contains("exe"), "Namenssuche unter PC Windows, nur der Name")
	check(SS.anfrage_id("1993", "windows", Z, 135).contains("systemeid=135") and SS.anfrage_id("1993", "windows", Z, 999).contains("systemeid=138")
			and SS.anfrage_id("1993", "windows", Z, 135).contains("gameid=1993"), "Abruf nach Kennung im System des Treffers (nur bekannte)")
	var t := SS.suche_lesen(_fixture("jeuRecherche_pc.json"), "de")
	check(t.size() == 4 and int(t[1].jahr) == 2016 and int(t[0].jahr) == 1993 and int(t[0].system) == 135, "Treffer mit System und Jahr gelesen")
	check(str(SS.bester_treffer(t, "DOOM", "windows", 2016).get("id", "")) == "2016" and str(SS.bester_treffer(t, "DOOM", "windows", 1993).get("id", "")) == "1993"
			and str(SS.bester_treffer(t, "DOOM", "windows", 1995).get("id", "")) == "1993", "gleicher Name: das nähere Jahr gewinnt (PS1-Fassung nie)")
	check(str(SS.bester_treffer(t, "DOOM", "windows").get("id", "")) == "1993" and str(SS.bester_treffer(t, "DOOM Eternal", "windows", 2020).get("id", "")) == "2020"
			and SS.bester_treffer(t, "Quake", "windows").is_empty() and str(SS.bester_treffer(t, "DOOM", "ps1").get("id", "")) == "4400",
			"ohne Jahr der erste; anderer Name: keiner; Retro bleibt beim eigenen System")
	var m: Dictionary = t[1].medien
	var alle := JSON.stringify(t[1])
	check(str(m.cover.url).contains("box-2D(eu)") and str(m.hero.url).contains("fanart") and str(m.logo.url).contains("wheel-hd") and not alle.contains("GEHEIM")
			and not alle.contains("evil") and not alle.contains("mp4"), "PC-Bilder: Box-Front, Fanart, Schriftzug – ohne Zugang, fremde Hosts, Video")
	check(SS.jahr_aus([{ "text": "2016-05-13" }, { "text": "1999" }, { "text": "x;rm" }, 7]) == 1999 and SS.jahr_aus("2016") == 0
			and SS.jahr_aus([{ "text": "0001-01-01" }]) == 0,
			"Jahr: frühestes gültiges, Unsinn übergangen")
	var k := SS.kontingent(_fixture("jeuRecherche_pc.json"))
	check(int(k.faeden) == 2 and int(k.pro_min) == 30 and SS.faeden(k) == 2 and SS.pause_ms(k) >= 2000, "Grenzen aus ssuser: Fäden und Minutenlimit")
	check(SS.faeden({}) == 1 and SS.faeden({ "faeden": 50 }) == SS.FAEDEN_MAX and SS.pause_ms({}) == SS.PAUSE_MS and SS.pause_ms({ "pro_min": 600 }) == SS.PAUSE_MS,
			"ohne Angabe ein Faden; nie mehr als FAEDEN_MAX; Pause nie kürzer als PAUSE_MS")
	_zugang_da()
	check(Media.ss_bildwahl_ok(steam) and Media.ss_bildwahl_ok({ "source": "epic", "system": "epic" }) and Media.ss_bildwahl_ok({ "source": "rom", "system": "ps2" }),
			"Bildwahl je Spiel: ScreenScraper auch bei Steam- und PC-Spielen")
	check(Media.scrape_quellen_fuer(steam, ["ss", "sgdb"], false) == ["sgdb", "ss"] and Media.scrape_quellen_fuer(steam, ["ss", "sgdb"], true) == ["ss", "sgdb"]
			and Media.scrape_quellen_fuer(steam, ["ss"], false) == ["ss"] and Media.scrape_quellen_fuer({ "source": "rom" }, ["ss", "sgdb"], false) == ["ss", "sgdb"],
			"Scrapen: Wahl gilt für alle; ohne eigene Wahl PC zuerst SteamGridDB, Retro zuerst ScreenScraper")
	var alt: Variant = Config.get_value("library.scrape_quellen_eigen", false)
	Config.set_value("library.scrape_quellen_eigen", false)
	var vorher := Media.scrape_wahl_gesetzt()
	Config.set_value("library.scrape_quellen_eigen", true)
	check(not vorher and Media.scrape_wahl_gesetzt() and FileAccess.get_file_as_string("res://src/ui/layers/spiele_scrapen.gd").contains("\"library.scrape_quellen_eigen\", true"),
			"eigene Wahl erkannt (Merkmal, der Standardwert zählt nicht)")
	Config.set_value("library.scrape_quellen_eigen", alt)
	check(SpieleScrapen.wahl_text(["ss", "sgdb"], true, true).begins_with("Retro erst ScreenScraper") and SpieleScrapen.wahl_text(["ss", "sgdb"], true, true).contains("ScreenScraper.fr")
			and SpieleScrapen.wahl_text(["ss", "sgdb"], true).begins_with("Erst ScreenScraper"), "Text zur Vorgabe mit PC-Spielen, Quellenangabe bleibt")
	var src := FileAccess.get_file_as_string("res://src/ui/layers/spiele_scrapen.gd")
	var me := FileAccess.get_file_as_string("res://src/core/media.gd")
	check(src.contains("Media.scrape_spiele()") and not src.contains("Media.sgdb_games()") and me.contains("var games: Array = scrape_spiele()"),
			"Menü und Lauf: alle Spiele, nicht nur Emulator-Spiele")
	for f in ["res://src/ui/layers/library_grid.gd", "res://src/ui/sections/settings_spiele.gd", "res://src/ui/layers/setup_wizard_spiele.gd"]:
		check(FileAccess.get_file_as_string(f).contains("Media.scrape_spiele()"), "Spiele scrapen auch mit nur PC-Spielen: " + f.get_file())
	check(Media.scrape_spiele().all(func(g: Dictionary) -> bool: return str(g.get("source", "")) != "app"), "keine Apps beim Scrapen")


## PC-Spiel in Media, ohne Netz (Media.ss_test): genau eine Namenssuche unter PC Windows, beste Wahl,
## bei Bedarf PC Dos; Grenzen übernommen; Ablehnung ehrlich; Bildwahl eines Steam-Spiels.
func _pc_media() -> void:
	print("PC-Spiele in Media (nachgebaute Antworten)")
	_zugang_da()
	var fix: Variant = _fixture("jeuRecherche_pc.json")
	var leer := { "response": { "ssuser": { "maxthreads": "1" }, "jeux": [{}] } }
	var urls: Array = []
	Media._ss_aus = ""
	Media._ss_grenzen = {}
	Media.ss_test = func(url: String) -> Dictionary:
		urls.append(url)
		return { "ok": true, "data": fix if url.contains("systemeid=138") else leer, "code": 200 }
	var g := { "id": "steam:379720", "title": "DOOM", "source": "steam", "system": "steam", "appid": "379720", "year": 2016, "path": "C:/Spiele/DOOM/DOOMx64vk.exe" }
	var r: Dictionary = await Media._ss_suchen(g)
	check(r.has("info") and str(r.info.id) == "2016" and str((r.info.medien as Dictionary).cover.url).contains("box-2D(eu)"), "Steam-Spiel gefunden: DOOM (2016) unter PC Windows")
	check(urls.size() == 1 and str(urls[0]).begins_with(SS.SUCHE_API) and str(urls[0]).contains("systemeid=138") and str(urls[0]).contains("recherche=doom")
			and not str(urls[0]).contains("romnom") and not str(urls[0]).contains("md5"), "eine Anfrage: Namenssuche, nie Datei oder Prüfsumme")
	check(int(Media._ss_grenzen.get("faeden", 0)) == 2 and int(Media._ss_grenzen.get("pro_min", 0)) == 30, "Fäden und Minutenlimit aus der Antwort übernommen")
	Media._ss_grenzen = {}
	urls.clear()
	Media.ss_test = func(url: String) -> Dictionary:
		urls.append(url)
		return { "ok": true, "data": fix if url.contains("systemeid=135") else leer, "code": 200 }
	r = await Media._ss_suchen({ "id": "gog:1", "title": "DOOM", "source": "gog", "system": "gog", "year": 1993 })
	check(r.has("info") and str(r.info.id) == "1993" and urls.size() == 2 and str(urls[1]).contains("systemeid=135"), "nicht unter Windows: dann PC Dos")
	urls.clear()
	r = await Media._ss_suchen({ "id": "epic:x", "title": "Quake", "source": "epic", "system": "epic" })
	check(str(r.get("grund", "")) == "fehlt" and urls.size() == 2, "nirgends gefunden: ehrlich „nicht gefunden“, zwei Anfragen")
	urls.clear()
	Media.ss_test = func(url: String) -> Dictionary:
		urls.append(url)
		return { "ok": false, "data": null, "code": 430, "text": "quota" }
	r = await Media._ss_suchen(g)
	var gesperrt := Media.ss_grund()
	r = await Media._ss_suchen(g)
	check(str(r.get("grund", "")) == "kontingent" and gesperrt == "kontingent" and urls.size() == 1, "Tageslimit: sofort Schluss, keine weiteren Anfragen")
	Media._ss_aus = ""
	Media.ss_test = func(url: String) -> Dictionary:
		urls.append(url)
		return { "ok": true, "data": fix, "code": 200 }
	var k: Dictionary = await Media.ss_kandidaten(g, true)
	var alle := JSON.stringify(k)
	check(bool(k.get("ok", false)) and str(k.id) == "2016" and (k.liste.cover as Array).size() == 2 and (k.liste.hero as Array).size() == 2
			and not alle.contains("GEHEIM") and not alle.contains("evil") and not alle.contains("devpassword"), "Bildwahl eines Steam-Spiels: Kandidaten von ScreenScraper, sauber")
	Media.ss_test = Callable()
	Media._ss_grenzen = {}
	Media._ss_aus = ""


## Alles ersetzen bei einem Steam-Spiel mit ScreenScraper: das Bild von Steam wird ersetzt (die
## Datei von Steam bleibt), kein Rücken, kein Symbol von ScreenScraper.
func _pc_ersetzen() -> void:
	print("Alles ersetzen bei einem PC-Spiel")
	var dir := Config.path("cache/img/steam")
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.make_dir_recursive_absolute(Config.path("cache/img/ss"))
	var png := FileAccess.get_file_as_bytes("res://icon.png") if FileAccess.file_exists("res://icon.png") else PackedByteArray([0x89, 0x50, 0x4E, 0x47])
	var schreib := func(p: String) -> String:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_buffer(png)
		f.close()
		return p
	var steam_bild: String = schreib.call(dir.path_join("379720_cover.jpg"))
	var g := { "id": "test:doom", "title": "DOOM", "system": "steam", "source": "steam", "appid": "379720", "images_auto": { "cover": steam_bild } }
	var gefragt := {}
	var ss_fake := func(game: Dictionary, kind: String, _info: Dictionary) -> String:
		gefragt[kind] = true
		return schreib.call(Media.bild_ziel("ss", game, kind, "https://neoclone.screenscraper.fr/m?media=%s" % kind, "png"))
	Media.scrape_test = { "ss": ss_fake }
	var res := Media.scrape_leer(["ss"])
	await Media._scrape_one(g, Media.scrape_quellen_fuer(g, ["ss"], true), true, res, { "running": 1 })
	Media.scrape_test = {}
	check(gefragt.has("cover") and gefragt.has("hero") and gefragt.has("logo") and not gefragt.has("ruecken") and not gefragt.has("icon"),
			"gefragt: Cover, Hintergrund, Schriftzug – kein Rücken, kein Symbol")
	check(str(g.images_auto.cover).begins_with(Config.path("cache/img/ss")) and FileAccess.file_exists(steam_bild) and int(res.quellen.ss.geholt) == 3,
			"Steam-Cover durch ScreenScraper ersetzt, die Steam-Datei bleibt")
	for kind in ["cover", "hero", "logo"]:
		DirAccess.remove_absolute(str(g.images_auto.get(kind, "")))
	DirAccess.remove_absolute(steam_bild)

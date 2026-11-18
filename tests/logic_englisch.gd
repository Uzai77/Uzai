extends Node
## Englische Oberfläche ohne deutsche Reste: Uzai mit Demo-Bibliothek auf Englisch aufbauen und
## die zentralen Bildschirme lesen (Startseite mit Kopf, Guide-Start ohne und mit Spiel,
## Einstellungen mit jeder Kategorie, jeder Schritt der Einrichtung). Kein sichtbarer Text darf
## Umlaute oder typische deutsche Wörter zeigen; Namen aus den Demo-Daten zählen nicht
## (tests/englisch_pruef.gd). Dazu die Zeitangaben, die an Stellen ohne Übersetzung landen.
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_englisch.tscn

const Lang := preload("res://src/core/lang.gd")
const Pruef := preload("res://tests/englisch_pruef.gd")
const Wizard := preload("res://src/ui/layers/setup_wizard.gd")
const E := preload("res://src/core/einrichtung.gd")
const People := preload("res://src/ui/components/guide_people.gd")
const MovieArt := preload("res://src/ui/components/movie_art.gd")
const VideoCard := preload("res://src/ui/components/video_card.gd")
const TwitchP := preload("res://src/core/twitch_parse.gd")
const GuideStartS := preload("res://src/ui/components/guide_start.gd")
const Search := preload("res://src/core/search.gd")
const BadgePopup := preload("res://src/ui/badge_popup.gd")
const BadgesL := preload("res://src/core/badges_logic.gd")
const UnlocksS := preload("res://src/core/unlocks.gd")
const Buehne := preload("res://src/ui/spielseite/buehne.gd")

const KATEGORIEN := ["aussehen", "klang", "spiele", "emulation", "konten", "controller", "imspiel", "aufnahmen", "medien", "mitteilungen", "system"]

var fails := 0
var main: Node
var _p: Pruef


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


## Image filter and achievements (Uzai's own and Steam's) in the English UI: their texts are drawn or reformatted
## and therefore bypassed the UI translation, so they stayed German.
func _erfolge_und_filter() -> void:
	print("Erfolge, Abzeichen und Bildfilter (Englisch)")
	var abz := BadgePopup.entry_of({ "kind": "badge", "id": "zeit_ps1", "tier": 2 })
	var deko := BadgePopup.deco_of({ "kind": "badge", "id": "zeit_ps1", "tier": 2 })
	check(str(abz.name) == "50 hours PS1" and str(deko.line1) == "Badge unlocked · PlayStation", "Abzeichen-Pop-up: %s / %s" % [deko.line1, abz.name])
	check(str(BadgePopup.entry_of({ "kind": "level", "level": 5 }).name) == "Level 5 reached"
			and str(BadgePopup.entry_of({ "kind": "summary", "count": 14, "first": true }).name) == "You unlocked 14 badges"
			and str(BadgePopup.deco_of({ "kind": "summary", "level": 3 }).line1) == "Badge · level 3"
			and str(BadgePopup.deco_of({ "kind": "level", "level": 5 }).line1).begins_with("New Uzai level · "), "Level und Zusammenfassung im Pop-up")
	var gross := true
	for d in BadgesL.DEFS:
		for stufe in [1, 2, 3, 4]:
			var e := tr(BadgesL.tier_title(d, stufe))
			for w in ["Stunden", "Erfolg", "Spiele", "Tage", "Nächte", "insgesamt", "Konsole", "Plattform", "Bilder", "gemeistert", "Mal "]:
				if e.contains(w):
					gross = false
					print("       deutsch geblieben: ", e)
	check(gross and tr("1.000 Stunden insgesamt") == "1.000 hours in total" and tr("1,000 Stunden insgesamt") == "1,000 hours in total"
			and tr("250 Stunden insgesamt") == "250 hours in total", "Titel aller Abzeichen-Stufen, auch mit Tausendertrenner")
	check(UnlocksS._lang({ "german": "Erster Schritt", "english": "First step" }) == "First step"
			and UnlocksS._lang({ "german": "Nur deutsch" }) == "Nur deutsch" and UnlocksS._lang({ "token": "x", "french": "Premier" }) == "Premier"
			and UnlocksS._lang("fest") == "fest", "Steam-Erfolge aus Steams eigenen Dateien: Englisch zuerst, sonst was da ist")
	var zeile: Array = Buehne.oben("PlayStation 2", "PCSX2", "CRT · 480 Zeilen", PackedStringArray(), "")
	check(tr(str(zeile[2])) == "Picture: CRT, 480 lines", "Zeile unter dem Spiel: %s" % tr(str(zeile[2])))
	var g := FileAccess.get_file_as_string("res://src/ui/sections/games.gd")
	check(g.contains("_stat(\"Bild\", tr(str(flt.get(\"name\", \"\"))))"), "Spiele-Seite: der Filtername wird vor dem Umformen übersetzt")


func _ready() -> void:
	Lang.apply("en")
	print("Zeitangaben und Muster (Englisch)")
	check(tr("Zuletzt gespielt") == "Recently played", "„Zuletzt gespielt“ im Katalog")
	check(People.dur(14 * 3600) == "14 hrs" and People.dur(1800) == "30 min" and People.dur(3600) == "1 hr"
			and People.dur(5400) == "1.5 hrs", "Spielzeit kurz: %s, %s, %s" % [People.dur(14 * 3600), People.dur(1800), People.dur(5400)])
	check(MovieArt.left_text(0.0, 3000.0) == "50 min left" and VideoCard.left_text(4500) == "1 hr 15 min left", "Restzeit")
	var now := 1_800_000_000
	check(TwitchP.uptime_text(now - 4500, now) == "Live for 1 hr 15 min" and TwitchP.uptime_text(now - 600, now) == "Live for 10 min",
			"Live seit: %s" % TwitchP.uptime_text(now - 4500, now))
	check(GuideStartS.stage_sub(0, 14 * 3600) == "Recently played  ·  14 hrs", "Guide: Zeile unter dem Spiel (%s)" % GuideStartS.stage_sub(0, 14 * 3600))
	check(GuideStartS.time_bit(1800, 600, 14 * 3600) == "Today 40 min  ·  Total 14 hrs", "Guide im Spiel: %s" % GuideStartS.time_bit(1800, 600, 14 * 3600))

	_erfolge_und_filter()
	Library.load_demo()
	_p = Pruef.new()
	_p.namen_aus_demo()
	check(_p.deutsch("Zuletzt gespielt") != "" and _p.deutsch("Recently played") == "" and _p.deutsch("Über Uzai") != "",
			"Erkennung: Deutsch ja, Englisch nein")
	# Uzai daneben aufbauen, ohne Startanimation (wie --no-boot bei den Proben).
	Config.set_value("theme.boot", "aus")
	await get_tree().process_frame
	main = load("res://src/main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await _warte(1.2)
	Config.set_value("controller.glyphs", "xbox")

	print("Startseite")
	main.goto("games")
	await _warte(0.5)
	_bild("Startseite mit Kopf und Tastenzeile")

	print("Guide")
	main.toggle_guide()
	await _warte(0.6)
	check(Nav.top_layer() != null, "Guide offen")
	_bild("Guide-Start ohne Spiel")
	await _zu()
	var rec: Array = Library.recent(1)
	if not rec.is_empty():
		Launcher.in_game = true
		Launcher.current = Library.get_game(str(rec[0].id))
		main.toggle_guide()
		await _warte(0.6)
		_bild("Guide-Start im Spiel")
		await _zu()
		Launcher.in_game = false
		Launcher.current = {}

	print("Einstellungen")
	for k in KATEGORIEN:
		main.goto("settings", k)
		await _warte(0.25)
		_bild("Einstellungen › " + k)

	# Die Suche der Einstellungen muss in der Sprache der Oberfläche finden – die Titel stehen im Code auf Deutsch.
	print("Suche in den Einstellungen")
	var sv: Node = main.sections["settings"]
	var index: Array = sv._suche_index()
	var titel := func(q: String) -> Array:
		return Search.rank(index, q, 8).map(func(z: Dictionary) -> String: return tr(str(z.title)))
	var vol: Array = titel.call("volume")
	check(not vol.is_empty() and vol.any(func(t: String) -> bool: return t.to_lower().contains("volume")), "„volume“ findet Zeilen (%s)" % str(vol).left(120))
	check(not (titel.call("storage") as Array).is_empty() and not (titel.call("language") as Array).is_empty(), "„storage“ und „language“ finden etwas")
	check(not (titel.call("Lautstärke") as Array).is_empty(), "das deutsche Wort findet weiterhin")

	print("Einrichtung")
	for st in E.STEPS:
		Config.set_value("einrichtung.done", false)
		Config.set_value("einrichtung.restart", false)
		Config.set_value("einrichtung.mehr", true)
		Config.set_value("einrichtung.step", st)
		var w: Control = Wizard.open_for(main, false)
		await _warte(0.5)
		_bild("Einrichtung › " + st)
		w.set("_finished", true)
		w.call("close")
		await _warte(0.2)
	Config.set_value("einrichtung.done", true)

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	Lang.release()
	get_tree().quit(1 if fails > 0 else 0)


## Alle sichtbaren Texte prüfen; die deutschen stehen in der Meldung.
func _bild(wo: String) -> void:
	var funde: Array = []
	var texte := _p.sichtbare_texte(get_tree().root)
	for t in texte:
		var g := _p.deutsch(t)
		if g != "" and not funde.has("„%s“ (%s)" % [t, g]):
			funde.append("„%s“ (%s)" % [t, g])
	# Ohne Texte prüfte der Test nichts (Bildschirm nicht aufgebaut).
	check(texte.size() >= 8 and funde.is_empty(), "%s: %d Texte, nur Englisch%s" % [wo, texte.size(), "" if funde.is_empty() else " – " + ", ".join(funde.slice(0, 6))])


func _zu() -> void:
	var n := 0
	while Nav.top_layer() and n < 8:
		Nav.top_layer().close()
		n += 1
		await _warte(0.1)
	await _warte(0.2)


func _warte(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

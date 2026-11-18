extends "res://tests/probe_base.gd"
## Probe für den Bereich Erfolge: Übersicht (leer, Laden, Fehler, gefüllt), Listen je Quelle,
## Erfolge eines Spiels (gefüllt, Laden, ohne Konto, Fehler, Vergleich) und die Spielzeit.
## PROBE_ONLY=uebersicht,spiel,zeit fotografiert nur Teile; PROBE_SEED=1 setzt eigene
## Beispieldaten (für den Vergleich mit dem Stand vor der Demo-Erweiterung).

var _only := ""
var _seed_on := false


func run() -> void:
	_only = OS.get_environment("PROBE_ONLY")
	_seed_on = OS.get_environment("PROBE_SEED") == "1"
	if _want("uebersicht"):
		await _uebersicht()
	if _want("spiel"):
		await _spiel()
	if _want("zeit"):
		await _zeit()
	if _want("quer"):
		await _quer()
	_accounts(false)


func _want(part: String) -> bool:
	return _only == "" or _only.split(",").has(part)


func _demo(on: bool) -> void:
	if "demo" in Achievements:
		Achievements.set("demo", on)


# --- Übersicht --------------------------------------------------------------------------

func _uebersicht() -> void:
	var view = main.sections["achievements"]
	# So, wie die Demo startet.
	main.goto("achievements", "uebersicht")
	await shot("01_uebersicht_demo", 1.6)
	var keep := _save()
	# Wird geladen
	Achievements.loading = true
	Achievements.recent_unlocks = []
	Achievements.ra_progress = []
	Achievements.steam_progress = []
	Achievements.last_error = ""
	view.build()
	view.focus_default()
	await shot("02_uebersicht_laden", 0.7)
	Achievements.loading = false
	# Fehler ohne gespeicherte Daten
	Achievements.last_error = "Steam antwortet gerade nicht. Uzai versucht es später noch einmal."
	view.build()
	view.focus_default()
	await shot("03_uebersicht_fehler", 0.7)
	# Ohne Konto
	var friends: Array = Social.steam_friends
	Social.steam_friends = []
	_demo(false)
	Achievements.last_error = ""
	view.build()
	view.focus_default()
	await shot("04_uebersicht_ohne_konto", 0.7)
	Social.steam_friends = friends
	_demo(true)
	_restore(keep)
	# Gefüllt
	if _seed_on:
		_seed()
	main.goto("achievements", "uebersicht")
	view.build()
	view.focus_default()
	await shot("05_uebersicht_daten", 1.0)
	await press("right")
	await shot("06_uebersicht_blaettern", 0.5)
	await press("down")
	await shot("07_uebersicht_fast", 0.6)
	await press("down")
	await shot("08_uebersicht_unten", 0.6)
	# Listen je Quelle
	main.goto("achievements", "retro")
	await shot("09_liste_retro", 0.9)
	await press("down", 2)
	await shot("10_liste_retro_fokus", 0.5)
	main.goto("achievements", "steam")
	await shot("11_liste_steam", 0.9)


# --- Erfolge eines Spiels ---------------------------------------------------------------

func _spiel() -> void:
	if _seed_on:
		_seed()
	main.goto("games", "zuletzt")
	await wait(0.6)
	main.open_game_achievements(Library.get_game("steam:1245620"))
	await shot("20_spiel_erfolge", 1.2)
	await press("down", 3)
	await shot("21_spiel_erfolge_blaettern", 0.6)
	await press("down", 9, 0.1)
	await shot("22_spiel_erfolge_offen", 0.6)
	await press("rb")
	await shot("22b_spiel_filter_frei", 0.7)
	# Filter mit dem Steuerkreuz: hoch auf die Leiste, rechts auf „Offen“
	await press("up", 3)
	await press("right")
	await shot("22c_spiel_filter_steuerkreuz", 0.7)
	# Geheimen Erfolg aufdecken (steht in „Offen“ ganz unten)
	await press("down")
	await press("down", 14, 0.1)
	await shot("22d_spiel_geheim", 0.6)
	await press("a")
	await shot("22e_spiel_aufgedeckt", 0.6)
	await press("b")
	await wait(0.5)
	# Emulator-Spiel mit Punkten
	main.open_game_achievements(Library.get_game("ps2:30fa359a43774f"))
	await shot("23_spiel_erfolge_ra", 1.2)
	await press("b")
	await wait(0.5)
	# Vergleich mit einem Freund
	var l = load("res://src/ui/layers/game_achievements.gd").new()
	l.game = Library.get_game("steam:1245620")
	l.compare = Social.steam_friends[0]
	main.open_layer(l)
	await shot("24_spiel_vergleich", 1.6)
	await press("b")
	await wait(0.5)
	# Ohne Konto (RetroAchievements fehlt)
	_accounts(false)
	_demo(false)
	Achievements._games.erase("ps2:5e1005d21bcb60")
	main.open_game_achievements(Library.get_game("ps2:5e1005d21bcb60"))
	await shot("25_spiel_ohne_konto", 1.0)
	await press("b")
	await wait(0.5)
	_demo(true)
	# Lädt noch
	Achievements._games.erase("steam:367520")
	main.open_game_achievements(Library.get_game("steam:367520"))
	await shot("26_spiel_laedt", 0.08)
	await shot("26b_spiel_geladen", 1.2)
	await press("b")
	await wait(0.5)
	# Kein Netz
	Achievements._games["steam:1091500"] = { "source": "steam", "appid": 1091500, "title": "Cyberpunk 2077", "total": 0, "unlocked": 0, "list": [],
			"error": "Steam ist gerade nicht erreichbar." }
	main.open_game_achievements(Library.get_game("steam:1091500"))
	await shot("27_spiel_kein_netz", 1.0)
	await press("b")
	await wait(0.5)
	# Spiel ohne Erfolge
	Achievements._games.erase("pc:d736d82439562c")
	main.open_game_achievements(Library.get_game("pc:d736d82439562c"))
	await shot("28_spiel_keine", 1.0)
	await press("b")
	await wait(0.5)


# --- Spielzeit --------------------------------------------------------------------------

func _zeit() -> void:
	main.goto("achievements", "statistik")
	await shot("30_zeit", 1.4)
	await press("down")
	await shot("31_zeit_2", 0.8)
	await press("down")
	await shot("32_zeit_3", 0.8)
	await press("down")
	await shot("33_zeit_4", 0.8)
	await press("down")
	await shot("34_zeit_5", 0.8)
	await press("down")
	await shot("35_zeit_6", 0.8)
	# Leer: keine Sitzungen, keine Spielzeit
	var sess: Array = Library.sessions
	var keep := {}
	for g in Library.games:
		keep[str(g.id)] = [g.get("playtime", 0), g.get("steam_minutes", 0)]
		g["playtime"] = 0
		g["steam_minutes"] = 0
	Library.sessions = []
	main.sections["achievements"].build()
	main.sections["achievements"].focus_default()
	await shot("36_zeit_leer", 0.9)
	Library.sessions = sess
	for g in Library.games:
		var k: Array = keep.get(str(g.id), [0, 0])
		g["playtime"] = k[0]
		g["steam_minutes"] = k[1]
	main.sections["achievements"].build()


# --- Wo Erfolge sonst auftauchen (Startseite, Spielseite) -------------------------------

func _quer() -> void:
	main.goto("games", "zuletzt")
	await shot("40_start", 1.6)
	await press("right")
	await shot("41_start_rechts", 1.2)
	main.open_game(Library.get_game("steam:1245620"))
	await shot("42_spielseite", 2.2)
	await press("down", 2)
	await shot("43_spielseite_erfolge", 1.0)
	await press("b")
	await wait(0.4)


# --- Beispieldaten ----------------------------------------------------------------------

func _accounts(on: bool) -> void:
	for k in ["ra_user", "ra_key"]:
		Config.set_value("accounts." + k, "demo" if on else "")


func _save() -> Dictionary:
	return { "p": Achievements.ra_profile, "ra": Achievements.ra_progress, "st": Achievements.steam_progress,
		"rec": Achievements.recent_unlocks, "err": Achievements.last_error }


func _restore(d: Dictionary) -> void:
	Achievements.ra_profile = d.p
	Achievements.ra_progress = d.ra
	Achievements.steam_progress = d.st
	Achievements.recent_unlocks = d.rec
	Achievements.last_error = d.err


func _seed() -> void:
	_accounts(true)
	var now := int(Time.get_unix_time_from_system())
	Achievements.last_error = ""
	Achievements.loading = false
	Achievements.ra_profile = { "name": "Spieler1", "points": 12340, "true_points": 30210, "rank": 4512 }
	Achievements.ra_progress = [
		{ "title": "Ōkami", "source": "ra", "ra_id": 1, "console": 21, "console_name": "PlayStation 2", "unlocked": 44, "total": 52, "icon": "", "award": "",
			"date": now - 3600 },
		{ "title": "Shadow of the Colossus", "source": "ra", "ra_id": 2, "console": 21, "console_name": "PlayStation 2", "unlocked": 26, "total": 26, "icon": "",
			"award": "mastered", "date": now - 86400 * 3 },
		{ "title": "Final Fantasy X", "source": "ra", "ra_id": 3, "console": 21, "console_name": "PlayStation 2", "unlocked": 61, "total": 95, "icon": "",
			"award": "", "date": now - 86400 * 6 },
		{ "title": "Final Fantasy VII", "source": "ra", "ra_id": 4, "console": 12, "console_name": "PlayStation", "unlocked": 38, "total": 47, "icon": "",
			"award": "beaten-hardcore", "date": now - 86400 * 9 },
		{ "title": "The Legend of Zelda: The Minish Cap", "source": "ra", "ra_id": 5, "console": 5, "console_name": "Game Boy Advance", "unlocked": 12, "total": 40,
			"icon": "", "award": "", "date": now - 86400 * 20 },
		{ "title": "The Legend of Zelda: The Wind Waker", "source": "ra", "ra_id": 6, "console": 16, "console_name": "GameCube", "unlocked": 9, "total": 64,
			"icon": "", "award": "", "date": now - 86400 * 40 },
	]
	Achievements.steam_progress = [
		{ "title": "Elden Ring", "source": "steam", "appid": 1245620, "unlocked": 29, "total": 42, "icon": "", "date": now - 7200 },
		{ "title": "Hades", "source": "steam", "appid": 1145360, "unlocked": 41, "total": 49, "icon": "", "date": now - 86400 * 2 },
		{ "title": "Hollow Knight", "source": "steam", "appid": 367520, "unlocked": 33, "total": 63, "icon": "", "date": now - 86400 * 12 },
		{ "title": "Stardew Valley", "source": "steam", "appid": 413150, "unlocked": 40, "total": 40, "icon": "", "date": now - 86400 * 30 },
		{ "title": "Balatro", "source": "steam", "appid": 2379780, "unlocked": 18, "total": 34, "icon": "", "date": now - 86400 * 4 },
	]
	Achievements.recent_unlocks = [
		{ "title": "Wolkenwanderer", "desc": "Erreiche den Gipfel des Kamiki-Dorfs.", "game": "Ōkami", "date": now - 3600, "points": 10, "source": "ra", "icon": "",
			"rarity": 18.0, "hardcore": true },
		{ "title": "Malenia, Klinge Miquellas", "desc": "Besiege Malenia, Klinge Miquellas.", "game": "Elden Ring", "date": now - 7200, "source": "steam", "icon": "",
			"rarity": 3.1 },
		{ "title": "Elden Lord", "desc": "Erreiche das Ende „Zeitalter der Gebrochenheit“.", "game": "Elden Ring", "date": now - 90000, "source": "steam", "icon": "",
			"rarity": 12.4 },
		{ "title": "Hirte des Hades", "desc": "Entkomme mit jeder Waffe.", "game": "Hades", "date": now - 86400 * 2, "source": "steam", "icon": "", "rarity": 7.9 },
		{ "title": "Der letzte Koloss", "desc": "Bezwinge Malus.", "game": "Shadow of the Colossus", "date": now - 86400 * 3, "points": 25, "source": "ra",
			"icon": "", "rarity": 41.0, "hardcore": true },
		{ "title": "Großer Fang", "desc": "Fange eine Legende.", "game": "Stardew Valley", "date": now - 86400 * 5, "source": "steam", "icon": "", "rarity": 52.0 },
	]
	var names := [["Eldenfürst", "Werde zum Eldenfürsten."], ["Zeitalter der Sterne", "Erreiche das Ende „Zeitalter der Sterne“."],
		["Herr der rasenden Flamme", "Erreiche das Ende „Herr der rasenden Flamme“."], ["Malenia, Klinge Miquellas", "Besiege Malenia, Klinge Miquellas."],
		["Rennala, Königin des Vollmonds", "Besiege Rennala."], ["Sternengeißel Radahn", "Besiege Radahn."], ["Godrick der Verpflanzte", "Besiege Godrick."],
		["Morgott, der Omen-König", "Besiege Morgott."], ["Mohg, Herr des Blutes", "Besiege Mohg."], ["Rykard, Herr der Lästerung", "Besiege Rykard."],
		["Leyndell erreicht", "Betritt die Königshauptstadt."], ["Legendäre Waffen", "Erhalte alle legendären Bewaffnungen."],
		["Legendäre Zauber", "Erhalte alle legendären Zauber."], ["Legendäre Talismane", "Erhalte alle legendären Talismane."]]
	var list: Array = []
	for i in 42:
		var nm: Array = names[i % names.size()]
		var got := i < 29
		var t := str(nm[0]) if i < names.size() else "%s %d" % [nm[0], floori(float(i) / names.size()) + 1]
		list.append({ "id": "a%d" % i, "title": t, "desc": str(nm[1]), "icon": "", "icon_locked": "", "unlocked": got,
			"date": now - i * 40000 if got else 0, "points": 0, "rarity": [2.4, 4.8, 9.6, 14.0, 22.0, 31.0, 48.0, 63.0, 71.0][i % 9], "hardcore": false })
	list[33]["desc"] = "Geheimer Erfolg"
	Achievements._games["steam:1245620"] = { "source": "steam", "appid": 1245620, "title": "Elden Ring", "total": 42, "unlocked": 29, "list": list }
	var ra_list: Array = []
	for i in 52:
		var got2 := i < 44
		ra_list.append(
				{ "id": "r%d" % i,
				"title": ["Wolkenwanderer", "Pinselgott", "Sonnenaufgang", "Orochi bezwungen", "Kirschblüte", "Himmelszeichen"][i % 6] + ("" if i < 6
				else " %d" % (floori(i / 6.0) + 1)),
			"desc": "Beispielerfolg aus Ōkami.", "icon": "", "icon_locked": "", "unlocked": got2, "hardcore": got2 and i % 3 != 0,
			"date": now - i * 52000 if got2 else 0, "points": [5, 10, 25, 50][i % 4], "rarity": [3.0, 11.0, 26.0, 58.0][i % 4], "order": i })
	Achievements._games["ps2:30fa359a43774f"] = { "source": "ra", "ra_id": 1, "title": "Ōkami", "console": "PlayStation 2", "total": 52, "unlocked": 44,
		"points": 420, "points_total": 515, "list": ra_list, "shots": [] }

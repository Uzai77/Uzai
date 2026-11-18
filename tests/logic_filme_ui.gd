extends Node
## Logik der Filme-Oberfläche ohne Bildschirm: kurze Texte (Laufzeit, Restzeit, Folge,
## Bewertung, Qualität), Abzeichen und Filter der Quellen, was „Abspielen“ bei Serien meint,
## Staffel-Reihenfolge, ähnliche Titel, Farbtöne der Farbfelder.
## Aufruf: godot --headless --path . res://tests/logic_filme_ui.tscn

const Art := preload("res://src/ui/components/movie_art.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Texte")
	check(Art.runtime_text("124 min") == "2 Std. 4 Min.", "124 min → 2 Std. 4 Min. (%s)" % Art.runtime_text("124 min"))
	check(Art.runtime_text("2h 8min") == "2 Std. 8 Min.", "2h 8min")
	check(Art.runtime_text("45") == "45 Min.", "45 → 45 Min.")
	check(Art.runtime_text("120") == "2 Std.", "volle Stunden ohne Minuten")
	check(Art.runtime_text("") == "" and Art.runtime_text("0") == "", "ohne Laufzeit leer")
	check(Art.clock(3725.0) == "1:02:05" and Art.clock(65.0) == "1:05", "Uhrzeit im Film")
	check(Art.left_text(600.0, 3000.0) == "noch 40 Min.", "Restzeit in Minuten")
	check(Art.left_text(0.0, 5000.0) == "noch 1 Std. 23 Min.", "Restzeit mit Stunden (%s)" % Art.left_text(0.0, 5000.0))
	check(Art.episode_code(1, 3) == "S1 F3" and Art.episode_code(2, 4, true) == "Staffel 2  ·  Folge 4", "Folge kurz und lang")
	check(Art.episode_code(0, 2) == "Extra F2" and Art.season_name(0) == "Extras", "Staffel 0 sind die Extras")
	check(Art.rating_text("7.8") == "7,8" and Art.rating_text("") == "" and Art.rating_text("n/a") == "", "Bewertung mit Komma, sonst leer")
	check(Art.meta_line({ "type": "series", "genres": ["Krimi", "Drama"], "runtime": "48 min", "year": "2021" }) == "Serie  ·  Krimi  ·  48 Min.  ·  2021",
			"Zeile unter dem Titel")
	check(Art.initials("Mara Lindqvist") == "ML" and Art.initials("Cher") == "C", "Initialen")
	check(Art.can_resume(600.0, 3000.0) and not Art.can_resume(10.0, 3000.0) and not Art.can_resume(2900.0, 3000.0),
			"Fortsetzen erst nach 30 s, nicht kurz vor Schluss")

	print("Quellen")
	check(Art.quality_label(2160) == "4K" and Art.quality_label(1080) == "1080p" and Art.quality_label(480) == "SD" and Art.quality_label(0) == "",
			"Qualität als Wort")
	var s := { "quality": 2160, "hdr": "DV", "codec": "HEVC", "size_bytes": 19756849562, "cached": true, "addon_name": "A" }
	var b := Art.stream_badges(s)
	check(b.size() == 5 and b[0] == ["4K", "gold"] and b[1] == ["Dolby Vision", "gold"] and b[3] == ["18,4 GB", "muted"] and b[4] == ["Sofort bereit", "ok"],
			"Abzeichen: 4K, Dolby Vision, Codec, Größe, sofort (%s)" % str(b))
	check(Art.stream_name({ "name": "Addon\n4K" }) == "Addon 4K", "Name in einer Zeile")
	check(Art.stream_file({ "name": "X", "title": "Datei.mkv", "description": "Datei.mkv" }) == "Datei.mkv"
			and Art.stream_desc({ "name": "X", "title": "Datei.mkv", "description": "Datei.mkv" }) == "", "Dateiname oben, Beschreibung ohne Doppelung")
	var td := { "name": "X", "title": "Titel.2024.1080p.BluRay.x264\n💾 9.2 GB  1080p\n👤 12 ⚙️ Tracker" }
	check(Art.stream_file(td) == "Titel.2024.1080p.BluRay.x264" and Art.stream_desc(td) == "Seeder 12  ·  via Tracker",
			"Emojis als Wort, ohne Zeile, die nur Größe und Auflösung wiederholt (%s)" % Art.stream_desc(td))
	var list := [{ "addon_name": "A", "quality": 2160 }, { "addon_name": "B", "quality": 1080 }, { "addon_name": "A", "quality": 720 },
			{ "addon_name": "B", "quality": 480 }]
	check(Art.filter_streams(list, "", 0).size() == 4, "ohne Filter alles")
	check(Art.filter_streams(list, "A", 0).size() == 2, "nach Addon")
	check(Art.filter_streams(list, "", 1080).size() == 1 and Art.filter_streams(list, "", 480).size() == 1, "nach Qualität, SD = unter 720p")
	check(Art.addon_counts(list) == [["A", 2], ["B", 2]], "Anzahl je Addon in Reihenfolge")
	check(Art.preferred_index(list, "1080") == 1 and Art.preferred_index(list, "auto") == 0, "bevorzugte Qualität wählt die erste passende")

	print("Serien")
	var meta := { "id": "tt1", "type": "series", "seasons": [0, 2, 1], "videos": [
		{ "id": "tt1:0:1", "season": 0, "episode": 1, "available": true },
		{ "id": "tt1:1:1", "season": 1, "episode": 1, "available": true },
		{ "id": "tt1:1:2", "season": 1, "episode": 2, "available": true },
		{ "id": "tt1:2:1", "season": 2, "episode": 1, "available": false },
	] }
	check(Art.season_order(meta) == [1, 2, 0], "Staffeln 1, 2, Extras zuletzt")
	var seen := { "tt1:1:1": true }
	var w := func(_m: String, v: String) -> bool: return seen.has(v)
	var p := func(_m: String, _v: String) -> Dictionary: return { "position": 0.0, "duration": 0.0 }
	var nu := Art.next_up(meta, [], w, p)
	check(str(nu.video.id) == "tt1:1:2" and nu.label == "S1 F2 abspielen", "erste ungesehene Folge (%s)" % str(nu.get("label", "")))
	var cw := [{ "id": "tt1", "video_id": "tt1:1:1", "position": 900.0, "duration": 2800.0 }]
	var nu2 := Art.next_up(meta, cw, w, p)
	check(str(nu2.video.id) == "tt1:1:1" and bool(nu2.resume) and nu2.label == "S1 F1 fortsetzen", "angefangene Folge zuerst")
	var film := Art.next_up({ "id": "tt9", "type": "movie" }, [], w, func(_m: String, _v: String) -> Dictionary: return { "position": 1200.0, "duration": 6000.0 })
	check(film.label == "Fortsetzen" and bool(film.resume), "Film: Fortsetzen")
	var rows := [
			{ "items": [{ "id": "a", "type": "series", "genres": ["Krimi"] }, { "id": "tt1", "type": "series", "genres": ["Krimi"] },
			{ "id": "b", "type": "movie", "genres": ["Krimi"] }, { "id": "c", "type": "series", "genres": ["Komödie"] }] }]
	var sim := Art.similar({ "id": "tt1", "type": "series", "genres": ["Krimi"] }, rows)
	check(sim.size() == 1 and str(sim[0].id) == "a", "ähnlich: gleiche Art, gleiches Genre, nicht der Titel selbst")

	print("Farbfelder")
	var hues := {}
	for i in 10:
		hues[int(Art.hue_of("tt910000%d" % i) * 36.0)] = true
	check(hues.size() >= 6, "fortlaufende IDs bekommen verschiedene Farbtöne (%d von 10)" % hues.size())
	check(Art.poster_tex("x") != null and Art.backdrop_tex("x").get_width() == 96, "Farbfelder werden erzeugt")

	print("Nuvio-Profil hinter den Reitern")
	var mv = load("res://src/ui/sections/movies_view.gd").new()
	check(mv.chip_aktionen().is_empty(), "ohne Nuvio-Konto: keine Profil-Taste")
	Config.set_value("nuvio.refresh", "test")
	NuvioSync.sput("profiles", [{ "profile_index": 1, "name": "Lea" }])
	check(mv.chip_aktionen().is_empty(), "nur ein Profil: keine Profil-Taste")
	NuvioSync.sput("profiles", [{ "profile_index": 1, "name": "Lea" }, { "profile_index": 2, "name": "" }])
	Config.set_value("nuvio.profile", 2)
	var acts: Array = mv.chip_aktionen()
	check(acts.size() == 1 and str(acts[0].id) == "nuvio_profil" and str(acts[0].label) == "Profil 2" and (acts[0].tun as Callable).is_valid(),
			"zwei Profile: Taste mit dem aktiven Profil (ohne Namen: „Profil 2“)")
	Config.set_value("nuvio.profile", 1)
	check(str(mv.chip_aktionen()[0].label) == "Lea", "Taste zeigt den Namen des aktiven Profils")
	NuvioSync.sput("profiles", [])
	Config.set_value("nuvio.refresh", "")
	mv.free()

	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(0 if fails == 0 else 1)

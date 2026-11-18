extends Node
## Mehrere Nutzerprofile (Roadmap 109) ohne Bildschirm: Kennungen und Namen, strenges Laden,
## PIN-Hash (PBKDF2, Testvektoren) und Bremse, wer was darf, Kinderprofil (Alter, Spielzeit je
## Tag), Teilen der Einstellungen und der Bibliothek, Umstellen eines Einzelnutzer-Stands ohne
## Datenverlust (mit Sicherung), Trennung der Daten zweier Profile, Löschen (nie über
## Verknüpfungen) und kaputte Dateien.
## Aufruf: godot --headless --path . res://tests/logic_profile.tscn

const Profiles := preload("res://src/core/profiles.gd")
const Vault := preload("res://src/core/vault.gd")
const Backup := preload("res://src/core/backup.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _put(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _ready() -> void:
	# Bibliothek und Dienste sollen hier nichts im Hintergrund speichern.
	Library.demo = false
	_ids_and_names()
	_file()
	_pin()
	_brake()
	_guard()
	_kid()
	_split()
	_personal()
	await _migration()
	await _verteilt()
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(0 if fails == 0 else 1)


## Große Bibliothek: Der Zeitgeber speichert über mehrere Bilder verteilt – mit demselben Inhalt wie save() in einem
## Stück; save() hat Vorrang, und eine Änderung währenddessen bleibt „offen“.
func _verteilt() -> void:
	print("Große Bibliothek: Speichern über mehrere Bilder")
	var alt := [Library.games, Library.folders, Library.lists, Library.goals, Library.demo]
	Library.demo = false
	var viele: Array = []
	for i in 1000:
		viele.append({ "id": "pc:%d" % i, "title": "Spiel %d „mit“ \"Zeichen\" \\ und\tTab" % i, "source": "pc", "appid": 0, "images": { "cover": "c%d.jpg" % i },
			"folders": ["f_a"] if i % 7 == 0 else [], "favorite": i % 10 == 0, "playtime": i, "notes": "Zeile\nzwei" if i % 100 == 0 else "" })
	viele.append("kein Spiel")
	Library.games = viele
	Library.folders = [{ "id": "f_a", "name": "Ordner", "system": "" }]
	Library.lists = [{ "id": "l1", "name": "Liste", "games": ["pc:1"] }]
	Library.goals = { "2026": 12 }
	var soll_alle: Variant = JSON.parse_string(JSON.stringify({ "profiles": true, "games": Profiles.strip_games(viele), "folders": Library.folders }))
	var soll_eigen: Variant = JSON.parse_string(JSON.stringify({ "games": Profiles.personal_of(viele), "lists": Library.lists, "goals": Library.goals }))
	Library._dirty = true
	Library._speichern_weich()
	check(Library._weich_laeuft, "über der Grenze von %d Spielen läuft es verteilt" % Library.WEICH_AB)
	var bilder := 0
	while Library._weich_laeuft and bilder < 300:
		await get_tree().process_frame
		bilder += 1
	var ist_alle: Variant = JSON.parse_string(FileAccess.get_file_as_string(Config.path("library.json")))
	var ist_eigen: Variant = JSON.parse_string(FileAccess.get_file_as_string(Config.path("spieler.json")))
	check(ist_alle == soll_alle and ist_eigen == soll_eigen and (ist_alle.games as Array).size() == 1000, "gleicher Inhalt wie in einem Stück (Bibliothek und Persönliches)")
	check(not Library._dirty and bilder >= 6 and bilder < 30, "fertig nach %d Bildern, nichts mehr offen" % bilder)
	# Eine Änderung während des Speicherns: Es bleibt etwas offen (der Zeitgeber speichert danach noch einmal).
	Library._speichern_weich()
	await get_tree().process_frame
	Library.mark_dirty()
	Library._save_timer.stop()
	while Library._weich_laeuft:
		await get_tree().process_frame
	check(Library._dirty, "Änderung währenddessen: bleibt offen")
	# save() dazwischen hat Vorrang: Das verteilte Speichern schreibt den älteren Stand nicht mehr darüber.
	viele[0]["title"] = "Alt"
	Library._speichern_weich()
	await get_tree().process_frame
	viele[0]["title"] = "Neu"
	Library.save()
	while Library._weich_laeuft:
		await get_tree().process_frame
	for i in 3:
		await get_tree().process_frame
	var danach: Variant = JSON.parse_string(FileAccess.get_file_as_string(Config.path("library.json")))
	check(str(danach.games[0].title) == "Neu" and not Library._dirty, "save() dazwischen: der neuere Stand bleibt stehen")
	# Kleine Bibliothek: wie bisher in einem Stück.
	Library.games = viele.slice(0, 20)
	Library._speichern_weich()
	check(not Library._weich_laeuft and (JSON.parse_string(FileAccess.get_file_as_string(Config.path("library.json"))).games as Array).size() == 20,
			"kleine Bibliothek: sofort in einem Stück")
	Library.games = alt[0]
	Library.folders = alt[1]
	Library.lists = alt[2]
	Library.goals = alt[3]
	Library.save()
	Library.demo = alt[4]


func _ids_and_names() -> void:
	print("Kennungen und Namen")
	var seen := {}
	var all_ok := true
	for i in 200:
		var id := Profiles.new_id()
		all_ok = all_ok and Profiles.valid_id(id) and id.length() == Profiles.ID_LEN and not seen.has(id)
		seen[id] = true
	check(all_ok, "neue Kennungen: a–z0–9, 12 Zeichen, verschieden")
	for bad in ["", "abc", "ABCDEFGHIJ", "abcdefgh/..", "../../etc", "abcdefghijklmnopq", "abcdefgh ", "äbcdefgh", 12345678, null]:
		check(not Profiles.valid_id(bad), "ungültige Kennung abgelehnt: %s" % str(bad))
	check(Profiles.dir_of("/daten", "../../x") == "" and Profiles.dir_of("/daten", "abcdefgh12") == "/daten/profiles/abcdefgh12",
			"Ordner nur aus gültiger Kennung")
	check(Profiles.clean_name("  Max\t \n Mustermann ") == "Max Mustermann", "Name: Leerraum zusammengefasst")
	check(Profiles.clean_name("Evil\u202eetxt" + char(1)) == "Evil etxt", "Name: Richtungs- und Steuerzeichen weg")
	check(Profiles.clean_name("x".repeat(80)).length() == Profiles.NAME_MAX and Profiles.clean_name(5) == "", "Name: gekürzt, nur Text")
	check(Profiles.is_own_path("settings.json") and Profiles.is_own_path("zimmer/zimmer.json") and not Profiles.is_own_path("library.json")
		and not Profiles.is_own_path("cache/img/a.png") and not Profiles.is_own_path("zimmerei.json"), "welche Dateien einem Profil gehören")


func _file() -> void:
	print("Datei streng lesen")
	var raw := { "profiles": [
		{ "id": "aaaaaaaa11", "name": "Anna", "color": "blau", "avatar": "star_f", "created": 1700000000.0 },
		{ "id": "aaaaaaaa11", "name": "Doppelt" },
		{ "id": "../böse", "name": "X" },
		{ "id": "bbbbbbbb22", "name": "   " },
		{ "id": "cccccccc33", "name": "Kim", "color": "pink<script>", "avatar": "../../x.png", "kid": "ja",
			"pin": { "salt": "kurz", "hash": "x", "iter": 5 }, "rules": { "age": 99, "limit": 7, "shop": "ja", "chats": true } },
		"kein Profil", 42,
	], "last": "zzzzzzzz99", "legacy": "aaaaaaaa11", "brake": { "aaaaaaaa11": { "fails": 2, "until": 5 }, "fremd0000": { "fails": 9 } } }
	var c := Profiles.clean_file(raw)
	check((c.profiles as Array).size() == 2, "nur gültige, keine doppelten Profile (%d)" % (c.profiles as Array).size())
	var kim := Profiles.find(c, "cccccccc33")
	check(str(kim.color) == "lavendel" and str(kim.avatar) == "buchstabe" and not bool(kim.kid) and not kim.has("pin"), "Unbekanntes fällt auf den Standard")
	check(int(kim.rules.age) == 12 and int(kim.rules.limit) == 0 and not bool(kim.rules.shop) and bool(kim.rules.chats), "Regeln geprüft")
	check(str(c.last) == "" and str(c.legacy) == "aaaaaaaa11" and (c.brake as Dictionary).keys() == ["aaaaaaaa11"], "Verweise nur auf vorhandene Profile")
	var many: Array = []
	for i in 20:
		many.append({ "id": "pppppppp%02d" % i, "name": "P%d" % i })
	check((Profiles.clean_file({ "profiles": many }).profiles as Array).size() == Profiles.MAX_PROFILES, "höchstens %d Profile" % Profiles.MAX_PROFILES)
	var d := Config.data_dir.path_join("t_datei")
	DirAccess.make_dir_recursive_absolute(d)
	_put(d.path_join(Profiles.FILE), "{kaputt")
	_put(d.path_join(Profiles.FILE + ".bak"), JSON.stringify({ "profiles": [{ "id": "aaaaaaaa11", "name": "Anna" }] }))
	check(str(Profiles.read_file(d).profiles[0].name) == "Anna", "kaputte Datei: die letzte gute Fassung (.bak)")
	_put(d.path_join(Profiles.FILE), JSON.stringify({ "profiles": [{ "id": "aaaaaaaa11", "name": "x".repeat(10) }], "pad": "y".repeat(Profiles.MAX_BYTES) }))
	DirAccess.remove_absolute(d.path_join(Profiles.FILE + ".bak"))
	check((Profiles.read_file(d).profiles as Array).is_empty(), "zu große Datei wird nicht gelesen")
	check(Profiles.read_small_json(d.path_join("gibtsnicht.json")) == null, "fehlende Datei: nichts")


func _hex(b: PackedByteArray) -> String:
	return b.hex_encode()


func _pin() -> void:
	print("PIN (PBKDF2-HMAC-SHA256)")
	var pw := "password".to_utf8_buffer()
	var salt := "salt".to_utf8_buffer()
	check(_hex(Profiles.pbkdf2(pw, salt, 1)) == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b", "Testvektor 1 Runde")
	check(_hex(Profiles.pbkdf2(pw, salt, 2)) == "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43", "Testvektor 2 Runden")
	check(_hex(Profiles.pbkdf2(pw, salt, 4096)) == "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a", "Testvektor 4096 Runden")
	var t := Time.get_ticks_msec()
	var rec := Profiles.make_pin("4711")
	var ms := Time.get_ticks_msec() - t
	check(not rec.is_empty() and int(rec.iter) == Profiles.PIN_ITER and not JSON.stringify(rec).contains("4711"), "PIN nur als gesalzener Hash gespeichert")
	check(ms >= 20, "langsam genug (%d ms für eine PIN)" % ms)
	check(Profiles.check_pin(rec, "4711") and not Profiles.check_pin(rec, "4712") and not Profiles.check_pin(rec, "471"), "richtige PIN passt, falsche nicht")
	var rec2 := Profiles.make_pin("4711")
	check(str(rec2.salt) != str(rec.salt) and str(rec2.hash) != str(rec.hash), "gleiche PIN, anderes Salz, anderer Hash")
	check(Profiles.make_pin("12a4").is_empty() and Profiles.make_pin("123").is_empty() and Profiles.make_pin("123456789").is_empty(), "nur 4–8 Ziffern")
	var bad := rec.duplicate()
	bad.hash = Marshalls.raw_to_base64(PackedByteArray([1, 2, 3]))
	check(not Profiles.check_pin(bad, "4711") and not Profiles.check_pin({}, "4711"), "veränderter Eintrag: nie gültig")
	bad = rec.duplicate()
	bad.iter = 1
	check(Profiles.clean_pin(bad).is_empty(), "zu wenige Runden werden nicht angenommen")


func _brake() -> void:
	print("Bremse nach Fehlversuchen")
	var now := 1_800_000_000
	var b := {}
	var waits: Array = []
	for i in 8:
		b = Profiles.brake_fail(b, now)
		waits.append(Profiles.brake_wait(b, now))
	check(waits == [0, 0, 30, 60, 120, 240, 480, 900], "frei, frei, dann 30 s, verdoppelt bis 15 min: %s" % str(waits))
	b = Profiles.brake_fail(b, now)
	check(Profiles.brake_wait(b, now) == Profiles.BRAKE_MAX, "höchstens %d s" % Profiles.BRAKE_MAX)
	check(Profiles.brake_wait(b, now + 2000) == 0, "danach darf man wieder")
	check(Profiles.brake_wait({ "fails": 5, "until": now + 999999 }, now) == Profiles.BRAKE_MAX, "verstellte Uhr: nie länger als %d s" % Profiles.BRAKE_MAX)
	check(Profiles.brake_left({}) == 3 and Profiles.brake_left({ "fails": 2 }) == 1, "übrige Versuche für den Hinweis")


func _guard() -> void:
	print("Wer darf was")
	var mom := { "id": "mmmmmmmm01", "pin": {}, "kid": false }
	var dad := { "id": "dddddddd01", "kid": false }
	var kid := { "id": "kkkkkkkk01", "kid": true }
	var kidpin := { "id": "kkkkkkkk02", "kid": true, "pin": {} }
	check(Profiles.guard("add", kid, {}, true) == "parent" and Profiles.guard("add", kid, {}, false) == "" and Profiles.guard("add", dad, {}, true) == "",
			"neues Profil aus dem Kinderprofil nur mit Eltern-PIN")
	check(Profiles.guard("rules", kid, kid, true) == "parent", "Kind ändert eigene Regeln nur mit Eltern-PIN")
	check(Profiles.guard("rules", dad, kidpin, true) == "" and Profiles.guard("rules", dad, mom, true) == "target",
			"Eltern ändern Kinderregeln frei, fremde Erwachsene nur mit deren PIN")
	check(Profiles.guard("edit", kid, mom, true) == "target" and Profiles.guard("edit", dad, kidpin, true) == "" and Profiles.guard("edit", mom, mom, true) == "",
			"Bearbeiten fremder Profile mit PIN nur mit deren PIN")
	check(Profiles.guard("delete", mom, mom, true) == "no" and Profiles.guard("delete", kid, dad, true) == "parent"
			and Profiles.guard("delete", dad, mom, true) == "target"
		and Profiles.guard("delete", mom, kidpin, true) == "", "Löschen: nie das aktive, Kind nur mit Eltern-PIN")


func _kid() -> void:
	print("Kinderprofil")
	check(Profiles.game_age({ "age": "usk16" }) == 16 and Profiles.game_age({ "age": "pegi7" }) == 12 and Profiles.game_age({ "age": "pegi3" }) == 6
		and Profiles.game_age({}) == -1 and Profiles.game_age({ "age": "usk99" }) == -1, "Altersstufe aus USK/PEGI, sonst unbekannt")
	var r := Profiles.clean_rules({ "age": 12 })
	check(Profiles.age_allowed(r, { "age": "usk12" }) and not Profiles.age_allowed(r, { "age": "usk16" }) and not Profiles.age_allowed(r, {}),
			"bis 12, ohne Angabe nicht")
	r.unknown = true
	check(Profiles.age_allowed(r, {}), "ohne Angabe zeigen (eingestellt)")
	r = Profiles.clean_rules({ "limit": 60 })
	var st := Profiles.time_add({}, "2026-10-23", 50 * 60)
	check(Profiles.time_left(r, st, "2026-10-23") == 600 and Profiles.time_left(r, st, "2026-10-23", 400) == 200,
			"heute noch 10 Minuten (mit laufender Runde weniger)")
	check(Profiles.time_left(r, st, "2026-10-24") == 3600, "neuer Tag: wieder die volle Zeit")
	st = Profiles.time_add(st, "2026-10-23", 99999)
	check(Profiles.time_left(r, st, "2026-10-23") == 0 and Profiles.time_left(Profiles.clean_rules({}), st, "2026-10-23") == -1, "aufgebraucht; ohne Grenze -1")
	check(Profiles.clean_time({ "day": "../x", "secs": -5 }) == { "day": "", "secs": 0 }, "kaputter Zeitstand wird bereinigt")
	check(Profiles.day_key(1_800_000_000, 0) == "2027-01-15" and Profiles.day_key(1_800_000_000, 13 * 60) != "", "Tag nach Ortszeit")


func _split() -> void:
	print("Einstellungen: gemeinsam und eigen")
	for p in Profiles.SHARED:
		if p in Profiles.SHARED_SECRETS:
			continue
		check(not Vault.SECRETS.any(func(sec: String) -> bool: return sec == p or sec.begins_with(p + ".")), "„%s“ ist nichts aus dem Tresor" % p)
	check(Profiles.SHARED_SECRETS == ["accounts.sgdb_key", "accounts.iidb_key"] and Profiles.SHARED_SECRETS.all(func(p: String) -> bool: return p in Vault.SECRETS),
			"nur der SteamGridDB-Schlüssel ist gemeinsam (im gemeinsamen Tresor)")
	var all := { "schema": 2, "theme": { "preset": "papier" }, "library": { "rom_dirs": { "ps2": "D:/ROMs" }, "sort": "name" },
		"accounts": { "spotify_refresh": "tresor1:xyz" }, "emulators": { "pcsx2": { "exe": "C:/x.exe" } }, "youtube": { "mpv": "C:/mpv.exe", "refresh": "geheim" } }
	var parts := Profiles.split_settings(all)
	var shared: Dictionary = parts[0]
	var own: Dictionary = parts[1]
	check(shared.has("emulators") and shared.library.has("rom_dirs") and not shared.library.has("sort") and str(shared.youtube.mpv) == "C:/mpv.exe",
			"gemeinsam: Spieleordner, Emulatoren, Programme")
	check(not JSON.stringify(shared).contains("tresor1") and not JSON.stringify(shared).contains("geheim") and not shared.has("theme"),
			"gemeinsam: keine Anmeldungen, kein Theme")
	check(own.has("accounts") and own.theme.preset == "papier" and own.library.sort == "name" and not own.library.has("rom_dirs") and not own.has("emulators"),
			"eigen: Theme, Ansicht, Anmeldungen")
	var other := Profiles.merge_settings({ "theme": { "preset": "glut" }, "library": { "rom_dirs": { "alt": "x" } } }, shared)
	check(other.theme.preset == "glut" and other.library.rom_dirs == { "ps2": "D:/ROMs" } and other.emulators.pcsx2.exe == "C:/x.exe",
			"anderes Profil: eigenes Theme, gemeinsame Ordner gelten")
	# Was zum PC gehört, nicht zu einem Profil: der Browser-Kern (liegt einmal auf der Platte) und alles, was Uzai
	# verstellt hat und zurückstellen muss.
	var pc := { "browser": { "kern_fassung": "131.0", "kern_abi": "a1", "kern_gesund": true, "favoriten": ["x"], "zuletzt": ["y"] },
		"emu": { "hintergrund_zurueck": [{ "file": "C:/e.ini", "keys": [] }] }, "room": { "raumton_zurueck": { "alt": [1] }, "fov": 80 },
		"controller": { "steam_guide_aus": true, "swap_ab": true } }
	var teile := Profiles.split_settings(pc)
	check(str(teile[0].browser.kern_fassung) == "131.0" and teile[0].browser.kern_gesund == true and not teile[1].browser.has("kern_fassung"),
			"Browser-Kern: Stand gilt für alle Profile")
	check(teile[1].browser.favoriten == ["x"] and teile[1].browser.zuletzt == ["y"] and not teile[0].browser.has("favoriten"), "Lesezeichen und Verlauf bleiben eigen")
	check(teile[0].has("emu") and teile[0].room.has("raumton_zurueck") and teile[0].controller.steam_guide_aus == true and not teile[1].has("emu"),
			"gemeinsam: was Uzai verstellt hat und zurückstellen muss")
	check(int(teile[1].room.fov) == 80 and teile[1].controller.swap_ab == true and not teile[0].room.has("fov"), "Zimmer und Controller sonst eigen")
	var zweites := Profiles.merge_settings({ "browser": { "favoriten": ["z"] } }, teile[0])
	check(str(zweites.browser.kern_fassung) == "131.0" and zweites.browser.favoriten == ["z"], "zweites Profil: Kern ist eingerichtet, eigene Lesezeichen")
	var umzug := Profiles.merge_settings({ "browser": { "kern_fassung": "130.0" } }, {})
	check(str(umzug.browser.kern_fassung) == "130.0", "Umstellung: Steht noch nichts im gemeinsamen Stand, gilt der Wert des Profils weiter")


func _personal() -> void:
	print("Bibliothek: persönliche Felder")
	var games := [{ "id": "a", "title": "A", "favorite": true, "playtime": 100, "status": "spiele", "tags": ["Koop"] }, { "id": "b", "title": "B" }]
	var per := Profiles.personal_of(games)
	check(per.keys() == ["a"] and per.a == { "favorite": true, "playtime": 100, "status": "spiele" }, "persönlich: Favorit, Spielzeit, Status")
	var stripped := Profiles.strip_games(games)
	check(not stripped[0].has("favorite") and stripped[0].tags == ["Koop"] and games[0].has("favorite"), "library.json ohne Persönliches (Original bleibt)")
	var bad := Profiles.clean_personal({ "games": { "a": { "favorite": "ja", "playtime": -5, "stars": 7, "review": 5, "title": "Gehackt", "exe": "C:/evil.exe" },
		"b": "kein Eintrag" }, "lists": "x", "goals": [] })
	check(bad.games == { "a": { "stars": 7 } } and bad.lists == [] and bad.goals == {}, "spieler.json streng: nur bekannte Felder mit passendem Typ")
	Profiles.apply_personal(games, Profiles.clean_personal({ "games": { "b": { "favorite": true } } }))
	check(not games[0].has("favorite") and not games[0].has("playtime") and games[1].favorite == true and games[0].tags == ["Koop"],
			"Profilwechsel: Persönliches des anderen weg, eigenes da")


## Einzelnutzer-Stand → erstes Profil; zweites Profil; Trennung; Löschen; kaputte Dateien.
func _migration() -> void:
	print("Umstellen: Einzelnutzer wird erstes Profil")
	var keep := { "dir": Config.data_dir, "pid": Config.profile_id, "pdir": Config.profile_dir, "profiles": Config.profiles.duplicate(true),
		"settings": Config.settings.duplicate(true) }
	Config._keys()   # Schlüssel des Startprofils abholen (sonst überschreibt der Faden später)
	var d := Config.data_dir.path_join("t_umstellen")
	DirAccess.make_dir_recursive_absolute(d)
	var old_settings := { "uzai_version": Config.VERSION, "schema": Config.SETTINGS_VERSION, "system": { "player_name": "Robin" },
		"theme": { "preset": "papier" }, "library": { "rom_dirs": { "ps2": "D:/PS2" }, "sort": "playtime" },
		"accounts": { "ra_user": "robin", "ra_key": "GEHEIM-RA" }, "emulators": { "pcsx2": { "exe": "C:/PCSX2/pcsx2.exe" } } }
	_put(d.path_join("settings.json"), JSON.stringify(old_settings))
	_put(d.path_join("library.json"), JSON.stringify({ "games": [
		{ "id": "steam:1", "title": "Eins", "source": "steam", "favorite": true, "playtime": 7200, "plays": 3, "status": "durch", "stars": 8, "tags": ["Koop"] },
		{ "id": "rom:2", "title": "Zwei", "source": "rom", "system": "ps2", "last_played": 1700000000 }],
		"folders": [], "lists": [{ "id": "l1", "name": "Couch", "games": ["steam:1"] }], "goals": { "2026": 5 } }))
	_put(d.path_join("sessions.json"), '{"steam:1": [[1700000000, 3600]]}')
	_put(d.path_join("zimmer/zimmer.json"), '{"format": 1}')
	_put(d.path_join("youtube.json"), '{"history": [{"id": "abc"}]}')
	_put(d.path_join("cache/youtube-feed.json"), '{"feed": []}')
	_put(d.path_join("captures.json"), '[]')
	_put(d.path_join(Vault.TEST_FILE), Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(32)))
	Config.data_dir = d
	Config.profiles = {}
	Config.profile_id = ""
	Config.profile_dir = ""
	Config.notices.clear()
	Config._setup_profiles()
	Config._vault_keys = Vault.load_keys(Config.profile_dir).keys
	var list := Config.profile_list()
	check(list.size() == 1 and str(list[0].name) == "Robin" and str(Config.profiles.legacy) == Config.profile_id, "ein Profil „Robin“ aus dem bisherigen Stand")
	var backups := Backup.list(d)
	check(not backups.is_empty() and str(backups[0].name).contains("vor-profilen"),
			"vorher gesichert (%s)" % (str(backups[0].name) if not backups.is_empty() else "keine"))
	var z := ZIPReader.new()
	z.open(str(backups[0].path))
	var zf := z.get_files()
	z.close()
	check(zf.has("settings.json") and zf.has("library.json") and zf.has("sessions.json"), "die Sicherung enthält den alten Stand")
	var pd := Config.profile_dir
	check(pd == d.path_join("profiles").path_join(Config.profile_id), "Ordner des Profils aus der Kennung")
	check(not FileAccess.file_exists(d.path_join("settings.json")) and FileAccess.file_exists(d.path_join(Profiles.SHARED_FILE))
			and FileAccess.file_exists(pd.path_join("settings.json")), "settings.json → gemeinsam.json + eigene settings.json")
	check(FileAccess.file_exists(pd.path_join("sessions.json")) and FileAccess.file_exists(pd.path_join("zimmer/zimmer.json"))
			and FileAccess.file_exists(pd.path_join("youtube.json"))
		and not FileAccess.file_exists(d.path_join("sessions.json")) and not DirAccess.dir_exists_absolute(d.path_join("zimmer")),
			"Spielzeit, Zimmer und Verlauf ziehen ins Profil")
	check(not FileAccess.file_exists(d.path_join("cache/youtube-feed.json")) and FileAccess.file_exists(d.path_join("captures.json")),
			"Feed aus dem Konto fällt weg, Gemeinsames bleibt")
	check(FileAccess.file_exists(pd.path_join(Vault.TEST_FILE)) and not FileAccess.file_exists(d.path_join(Vault.TEST_FILE)), "Tresor-Schlüssel zieht ins Profil")
	check(Config.path("settings.json") == pd.path_join("settings.json") and Config.path("library.json") == d.path_join("library.json")
			and Config.path("zimmer/zimmer.json") == pd.path_join("zimmer/zimmer.json"), "Config.path leitet Dateien des Profils um")
	Config.load_settings()
	check(str(Config.get_value("theme.preset", "")) == "papier" and str(Config.get_value("accounts.ra_key", "")) == "GEHEIM-RA"
			and (Config.get_value("library.rom_dirs", {}) as Dictionary).get("ps2") == "D:/PS2", "alle Einstellungen da (Theme, Anmeldung, Spieleordner)")
	check(str(Config.get_value("system.player_name", "")) == "Robin", "Spielername ist der Profilname")
	Library.load_library()
	var g1 := Library.get_game("steam:1")
	check(bool(g1.get("favorite", false)) and int(g1.get("playtime", 0)) == 7200 and str(g1.get("status", "")) == "durch" and g1.get("tags") == ["Koop"],
			"Favorit, Spielzeit und Backlog bleiben")
	check(Library.lists.size() == 1 and int(Library.goals.get("2026", 0)) == 5, "Listen und Jahresziel bleiben")
	Library.save()
	Config.save_settings()
	var lib: Variant = Config.read_json(d.path_join("library.json"), {})
	check(bool(lib.get("profiles", false)) and not JSON.stringify(lib).contains("favorite") and not JSON.stringify(lib).contains("playtime\":7200")
			and JSON.stringify(lib).contains("Koop"), "library.json für alle: ohne Persönliches")
	var shared_text := FileAccess.get_file_as_string(d.path_join(Profiles.SHARED_FILE))
	check(not shared_text.contains("GEHEIM-RA") and not shared_text.contains("robin") and shared_text.contains("D:/PS2"), "gemeinsam.json ohne Anmeldungen")
	check(not FileAccess.get_file_as_string(pd.path_join("settings.json")).contains("GEHEIM-RA"), "Anmeldung im Profil versiegelt (eigener Tresor)")
	var a_id := Config.profile_id

	print("Zweites Profil: eigene Daten")
	var b := Config.add_profile("Kim", "blau", "star_f")
	check(not b.is_empty() and Config.profile_list().size() == 2 and Config.needs_picker(), "zweites Profil angelegt; beim Start wird gefragt")
	check(Config.add_profile("   ").is_empty(), "leerer Name: kein Profil")
	Config.save_settings()
	_as(str(b.id))
	check(str(Config.get_value("theme.preset", "")) != "papier" and str(Config.get_value("accounts.ra_key", "")) == ""
			and str(Config.get_value("system.player_name", "")) == "Kim", "Kim: eigenes Theme, keine fremde Anmeldung")
	check((Config.get_value("library.rom_dirs", {}) as Dictionary).get("ps2") == "D:/PS2" and str(Config.emulator("pcsx2").get("exe", "")) == "C:/PCSX2/pcsx2.exe",
			"Kim: gemeinsame Spieleordner und Emulatoren")
	check(not bool(Library.get_game("steam:1").get("favorite", false)) and int(Library.get_game("steam:1").get("playtime", 0)) == 0 and Library.lists.is_empty(),
			"Kim: keine fremden Favoriten, Spielzeit, Listen")
	check(Library.games.size() == 2, "Kim: dieselbe Bibliothek")
	Config.set_value("theme.preset", "glut")
	Config.set_value("library.rom_dirs", { "ps2": "E:/Neu" })
	Library.set_field("rom:2", "favorite", true)
	Library.save()
	Config.save_settings()
	_as(a_id)
	check(str(Config.get_value("theme.preset", "")) == "papier" and bool(Library.get_game("steam:1").get("favorite", false))
			and not bool(Library.get_game("rom:2").get("favorite", false)), "zurück bei Robin: eigenes Theme und Favoriten unverändert")
	check((Config.get_value("library.rom_dirs", {}) as Dictionary).get("ps2") == "E:/Neu", "gemeinsamer Spieleordner gilt für alle")
	check(str(Config.get_value("accounts.ra_key", "")) == "GEHEIM-RA", "eigene Anmeldung weiter da")

	print("Kinderprofil über Config")
	check(Config.update_profile(str(b.id), { "kid": true, "rules": { "age": 6, "limit": 30, "chats": true } }), "Kim wird Kinderprofil")
	_as(str(b.id))
	check(Config.is_kid() and Config.kid_blocks("shop") and Config.kid_blocks("browser") and not Config.kid_blocks("chats"), "Shop und Browser aus, Chats erlaubt")
	Library.set_field("steam:1", "age", "usk16")
	Library.set_field("rom:2", "age", "usk6")
	var vis := Library.visible_games().map(func(x: Dictionary) -> String: return str(x.id))
	check(vis == ["rom:2"], "nur Spiele bis 6 Jahre sichtbar: %s" % str(vis))
	Config.kid_time_add(25 * 60)
	check(Config.kid_time_left() == 300 and Config.kid_time_left(400) == 0, "Spielzeit: noch 5 Minuten")
	# Die laufende Runde wird unterwegs gutgeschrieben (kid_time.gd): Ein Absturz mitten im Spiel kostet höchstens
	# zwei Minuten, nicht die ganze Runde.
	var KidTime: GDScript = load("res://src/core/kid_time.gd")
	check(KidTime.faellig(100, 0, false) == 0 and KidTime.faellig(130, 0, false) == 130 and KidTime.faellig(200, 130, false) == 0
			and KidTime.faellig(250, 130, false) == 120, "unterwegs: erst ab zwei Minuten, dann nur der neue Teil")
	check(KidTime.faellig(200, 130, true) == 70 and KidTime.faellig(100, 130, true) == 0 and KidTime.faellig(40, 0, true) == 40,
			"am Ende der Runde: der ganze Rest, nie etwas doppelt")
	var kt: Node = KidTime.new()
	kt._festhalten(130, false)
	check(Config.kid_time_left() == 170, "nach 130 Sekunden im Spiel steht die Zeit schon in der Datei (noch %d)" % Config.kid_time_left())
	kt._festhalten(150, false)
	check(Config.kid_time_left() == 170, "20 Sekunden später noch nichts Neues")
	kt._festhalten(200, true)
	check(Config.kid_time_left() == 100, "am Ende kommt nur der Rest dazu (noch %d)" % Config.kid_time_left())
	kt.free()
	_as(a_id)
	check(not Config.is_kid() and Library.visible_games().size() == 2 and Config.kid_time_left() == -1, "Erwachsene sehen alles, ohne Grenze")

	print("PIN und Bremse über Config")
	check(Config.update_profile(a_id, { "pin": Profiles.make_pin("2468") }) and Config.profile().has("pin"), "PIN gesetzt")
	var saved_file: Variant = Profiles.read_small_json(d.path_join(Profiles.FILE))
	check(not JSON.stringify(saved_file).contains("2468"), "profiles.json ohne die PIN selbst")
	for i in 3:
		Config.pin_result([a_id], false)
	check(Config.pin_wait([a_id]) > 0 and Config.pin_tries_left([a_id]) == 0, "nach drei Fehlversuchen: warten")
	Config.profiles = Profiles.read_file(d)
	check(Config.pin_wait([a_id]) > 0, "die Bremse übersteht einen Neustart")
	Config.pin_result([a_id], true)
	check(Config.pin_wait([a_id]) == 0, "richtige PIN löst die Bremse")
	check(Config.parent_ids() == [a_id] and Config.profile_guard("delete", a_id) == "no", "Eltern-PIN bekannt; aktives Profil nicht löschbar")

	print("Löschen")
	var outside := Config.data_dir.path_join("t_draussen")
	_put(outside.path_join("wichtig.txt"), "bleibt")
	var kdir := Profiles.dir_of(d, str(b.id))
	var linked := OS.execute("ln", ["-s", outside, kdir.path_join("verknuepfung")]) == 0
	check(not bool(Config.delete_profile(a_id).ok), "das aktive Profil nicht")
	var r := Config.delete_profile(str(b.id))
	check(bool(r.ok) and Config.profile_list().size() == 1 and Profiles.find(Config.profiles, str(b.id)).is_empty(), "Kim gelöscht")
	check(FileAccess.file_exists(outside.path_join("wichtig.txt")), "Ziel einer Verknüpfung bleibt unangetastet%s" % ("" if linked else " (ohne ln geprüft)"))
	check(not DirAccess.dir_exists_absolute(kdir) or not linked, "Ordner weg (Reste mit Verknüpfung beiseitegelegt, nie gefolgt)")
	check(not FileAccess.file_exists(kdir.path_join("settings.json")) and FileAccess.file_exists(pd.path_join("settings.json")),
			"nur Kims Daten weg, Robins bleiben")
	check(not bool(Config.delete_profile(a_id).ok) and not bool(Config.delete_profile("../../t_draussen").ok), "letztes Profil und fremde Pfade: nie")
	check(not Config.needs_picker(), "nur noch ein Profil: keine Auswahl beim Start")

	print("Kaputte Dateien")
	_put(pd.path_join("spieler.json"), "{nicht json")
	_put(pd.path_join("spieler.json.bak"), "auch kaputt")
	Library.load_library()
	check(Library.games.size() == 2 and not bool(Library.get_game("steam:1").get("favorite", false)), "kaputte spieler.json: Bibliothek bleibt, ohne Persönliches")
	Config.save_settings()
	Backup.snapshot_settings(pd)
	for f in ["settings.json", "settings.json.bak", "settings.json.tmp"]:
		_put(pd.path_join(f), "{kaputt")
	Config.notices.clear()
	Config.load_settings()
	check(str(Config.get_value("theme.preset", "")) == "papier" and Config.notices.any(func(n: String) -> bool: return n.contains("repariert")),
			"kaputte eigene Einstellungen: aus der täglichen Kopie")
	for f in [Profiles.FILE, Profiles.FILE + ".bak", Profiles.FILE + ".tmp"]:
		_put(d.path_join(f), "{]")
	Config.profiles = {}
	Config.notices.clear()
	Config._setup_profiles()
	check(Config.profile_list().size() == 1 and str(Config.profile_list()[0].id) == a_id and str(Config.profile().name) == "Robin",
			"kaputte profiles.json: Profil aus seinem Ordner wiederhergestellt")
	check(Backup.allowed("profiles/%s/settings.json" % a_id) and Backup.allowed("profiles/%s/zimmer/zimmer.json" % a_id)
			and not Backup.allowed("profiles/%s/schluessel.test" % a_id)
		and not Backup.allowed("profiles/%s/cache/x.json" % a_id) and not Backup.allowed("profiles/../settings.json") and not Backup.allowed("profiles/BAD/x.json"),
			"Sicherung: Profildaten ja, Schlüssel und Fremdes nie")

	Config.data_dir = keep.dir
	Config.profile_id = keep.pid
	Config.profile_dir = keep.pdir
	Config.profiles = keep.profiles
	Config.settings = keep.settings
	Library.load_demo()
	await get_tree().process_frame


## So tun, als liefe Uzai mit diesem Profil (wie nach einem Neustart mit --profil=…).
func _as(id: String) -> void:
	Config.profile_id = id
	Config.profile_dir = Profiles.dir_of(Config.data_dir, id)
	DirAccess.make_dir_recursive_absolute(Config.profile_dir)
	Config._vault_keys = Vault.load_keys(Config.profile_dir).keys
	Config.load_settings()
	Library.load_library()

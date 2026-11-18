extends Node
## Konten und Datenschutz (Punkte 13, 77): jeder Dienst hat Texte, Symbol und Seite; Abmelden leert
## genau die Einträge eines Dienstes (die eigene App nur auf Wunsch), jede verschlüsselte Anmeldung
## gehört zu einem Dienst – sonst bliebe sie beim „Überall abmelden“ liegen.
## Aufruf: godot --headless --path . res://tests/logic_konten.tscn

const Konten := preload("res://src/core/konten.gd")
const Vault := preload("res://src/core/vault.gd")
const Icons := preload("res://src/core/icons.gd")
const Quelle := preload("res://tests/quelle.gd")
const VoiceS := preload("res://src/core/voice.gd")
const SpotifyS := preload("res://src/core/music_spotify.gd")
const SteamCMS := preload("res://src/core/steam_cm.gd")
const SpotifyEigen := preload("res://src/ui/layers/spotify_eigen.gd")
const Sgdb := preload("res://src/core/sgdb_konto.gd")
const Profiles := preload("res://src/core/profiles.gd")
const ConfigS := preload("res://src/core/config.gd")

var fails := 0
var store := {}


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_data()
	_forget()
	_ohne_ids()
	_angeboten()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Öffentliche Pakete haben keinen ScreenScraper-Programmzugang: Dann steht ScreenScraper auch in der Datenschutz-
## Übersicht nicht zur Wahl (wie in den Bild-Einstellungen und der Bildwahl).
func _angeboten() -> void:
	print("Dienste zur Wahl")
	var SK = load("res://src/ui/sections/settings_konten.gd")
	check(not SK.angeboten("screenscraper", false) and SK.angeboten("screenscraper", true), "ScreenScraper nur mit Programmzugang")
	check(SK.angeboten("steam", false) and SK.angeboten("sgdb", false), "andere Dienste immer")
	var src := Quelle.lesen("res://src/ui/sections/settings_konten.gd")
	check(src.contains("if not on and not angeboten(id, ss_zugang):"), "Übersicht fragt angeboten() – Gespeichertes bleibt sichtbar (Abmelden)")


func _read(key: String, default: Variant) -> Variant:
	return store.get(key, default)


func _write(key: String, v: Variant) -> void:
	store[key] = v


func _data() -> void:
	print("Dienste")
	var ids := {}
	var all_keys := {}
	var ok_text := true
	var ok_icon := true
	for s in Konten.SERVICES:
		ids[s.id] = true
		ok_text = ok_text and str(s.name) != "" and str(s.stores).ends_with(".") and str(s.talks).ends_with(".") and not (s.keys as Array).is_empty()
		ok_icon = ok_icon and Icons.P.has(str(s.icon))
		for k in s.keys + s.get("app", []):
			if all_keys.has(k):
				check(false, "%s gehört nur zu einem Dienst" % k)
			all_keys[k] = str(s.id)
	check(ids.size() == Konten.SERVICES.size(), "jede Kennung nur einmal")
	check(ok_text and ok_icon, "Name, Texte (ganze Sätze), Einträge und Symbol je Dienst")
	var missing: Array = Vault.SECRETS.filter(func(k: String) -> bool: return k != "movies.addons" and not all_keys.has(k))
	check(missing.is_empty(), "jede verschlüsselte Anmeldung gehört zu einem Dienst %s" % str(missing))
	# Die Einträge gibt es im Code wirklich (Tippfehler hieße: Abmelden lässt die echte Anmeldung liegen).
	var src := ""
	for f in ["core/config.gd", "core/steam_chat.gd", "core/voice.gd", "core/discord_chat.gd", "core/music.gd", "core/youtube.gd",
			"core/youtube_tv.gd", "core/twitch.gd", "core/nuvio_sync.gd", "core/achievements.gd", "core/media.gd", "core/movies.gd", "core/medienquellen.gd",
				"library/epic_account.gd"]:
		src += Quelle.lesen("res://src/" + f)
	var unknown: Array = all_keys.keys().filter(func(k: String) -> bool: return not src.contains('"%s"' % k) and not src.contains('"%s"' % k.get_slice(".", 1)))
	check(unknown.is_empty(), "alle Einträge kommen im Code vor %s" % str(unknown))
	var view := Quelle.lesen("res://src/ui/sections/settings_view.gd")
	# Filme-Quellen (Plex, Jellyfin, Emby, Stremio) wohnen an einer Stelle: Medien → Filme-Quellen.
	var no_page: Array = Konten.SERVICES.filter(func(s: Dictionary) -> bool:
		if str(s.page) == "Filme-Quellen":
			return not (view.contains('_action("Filme-Quellen",') and view.contains("main.open_movie_sources()"))
		return str(s.page) != "" and not view.contains('_more("%s",' % s.page))
	check(no_page.is_empty(), "jede Seite zum Verbinden gibt es unter Konten %s" % str(no_page.map(func(s): return s.id)))


func _forget() -> void:
	print("Abmelden")
	var get_v := Callable(self, "_read")
	var set_v := Callable(self, "_write")
	store = { "accounts.discord_token": "t", "accounts.discord_refresh": "r", "accounts.discord_expires": 1790000000,
		"accounts.discord_client_id": "123", "accounts.discord_client_secret": "geheim", "accounts.discord_servers": ["1"],
		"accounts.steam_chat_refresh": "s" }
	check(Konten.stored("discord", get_v) and Konten.has_app("discord", get_v) and Konten.stored("steam", get_v), "angemeldet erkannt")
	check(not Konten.stored("twitch", get_v) and Konten.stored_count(get_v) == 2, "nicht angemeldete Dienste zählen nicht")
	Konten.forget("discord", set_v)
	check(str(store["accounts.discord_token"]) == "" and str(store["accounts.discord_refresh"]) == "" and int(store["accounts.discord_expires"]) == 0,
			"Zugang, Erneuerung und Ablauf geleert")
	check(str(store["accounts.discord_client_secret"]) == "geheim" and str(store["accounts.discord_client_id"]) == "123", "eigene App bleibt ohne Wunsch")
	check((store["accounts.discord_servers"] as Array).size() == 1 and str(store["accounts.steam_chat_refresh"]) == "s",
			"Einstellungen und andere Dienste bleiben")
	check(not Konten.stored("discord", get_v), "danach abgemeldet")
	Konten.forget("discord", set_v, true)
	check(str(store["accounts.discord_client_secret"]) == "" and str(store["accounts.discord_client_id"]) == "", "mit Wunsch auch die eigene App")
	store = { "accounts.twitch_access_until": 1790000000, "accounts.ra_user": "  " }
	check(not Konten.stored("twitch", get_v) and not Konten.stored("retroachievements", get_v), "Ablaufzeit allein oder Leerzeichen zählen nicht")
	check(Konten.empty_of("nuvio.expires") is int and Konten.empty_of("accounts.twitch_access_until") is int and Konten.empty_of("accounts.ra_key") is String,
			"Zahlen bleiben Zahlen")


## Anmelden ohne eigene IDs: Uzais Discord-App (öffentliche ID, PKCE ohne Secret), Spotify-Bremse
## und Schutzschalter, Steams kurze Sitzung neben Steam am PC.
func _ohne_ids() -> void:
	print("Ohne eigene IDs")
	check(VoiceS.APP_ID.is_valid_int() and VoiceS.APP_ID.length() >= 17, "Uzais Discord-App-ID ist eingebaut (nur Ziffern)")
	check(VoiceS.pick_app_id("", VoiceS.APP_ID) == VoiceS.APP_ID and VoiceS.pick_app_id("42", VoiceS.APP_ID) == "42"
			and VoiceS.pick_app_id("", "kaputt") == "", "eigene App-ID hat Vorrang, sonst die eingebaute")
	var vsrc := Quelle.lesen("res://src/core/voice.gd")
	check(not vsrc.to_lower().contains("const client_secret") and not vsrc.contains("APP_SECRET"), "kein Client-Secret mitgeliefert")
	var f := VoiceS.token_fields("1", "", "c", "v", "http://localhost")
	check(not f.has("client_secret") and str(f.code_verifier) == "v" and str(f.redirect_uri) == "http://localhost", "Tausch ohne Secret mit Prüfwert (PKCE)")
	var f2 := VoiceS.token_fields("1", "geheim", "c", "", "")
	check(str(f2.client_secret) == "geheim" and not f2.has("code_verifier") and not f2.has("redirect_uri"), "eigene App mit Secret wie bisher")
	check(not VoiceS.refresh_fields("1", "", "r").has("client_secret") and VoiceS.refresh_fields("1", "s", "r").has("client_secret"), "Erneuern ohne Secret")
	# Vergleichswert mit Python (hashlib.sha256 + urlsafe_b64encode ohne „=“) gerechnet.
	check(VoiceS.pkce_challenge("dBjftJeZ4CVP-mJ92K9qbBpXzVGnJRFD-3Pg5HbtbBE") == "_gLOmcXw1br6T_MPxNEBRODvXhAIOm_Txj4DmJROWpU", "PKCE-Herausforderung: base64url(SHA-256)")
	var ver := VoiceS.pkce_verifier()
	check(ver.length() >= 43 and ver.length() <= 128 and not ver.contains("=") and not ver.contains("+") and not ver.contains("/"), "Prüfwert 43–128 Zeichen, URL-sicher")
	check(VoiceS.pkce_verifier() != ver, "jeder Prüfwert neu")
	print("Spotify: Bremse und Schutzschalter")
	check(SpotifyS.rate_wait(30, 1) == 30 and SpotifyS.rate_wait(30, 2) == 60 and SpotifyS.rate_wait(30, 3) == 120, "jede weitere Bremse doppelt so lang")
	check(SpotifyS.rate_wait(30, 9) == 900 and SpotifyS.rate_wait(2, 1) == 10 and SpotifyS.rate_wait(3600, 1) == 3600, "mindestens 10 s, höchstens 15 Min. (oder Retry-After)")
	# Laufzeit eines Schlüssels aus der Antwort: Unsinn oder nichts gilt als eine Stunde, nie unter zwei Minuten (mit 0
	# erneuerte jede Anfrage die Anmeldung erst einmal).
	check(SpotifyS.gilt_s(3600) == 3600 and SpotifyS.gilt_s("7200") == 7200 and SpotifyS.gilt_s(null) == 3600 and SpotifyS.gilt_s({}) == 3600,
			"Laufzeit: Zahl, Ziffern-Text, sonst eine Stunde")
	check(SpotifyS.gilt_s(0) == 120 and SpotifyS.gilt_s(-5) == 120 and SpotifyS.gilt_s(1.0e12) == 86400, "Laufzeit: mindestens zwei Minuten, höchstens ein Tag")
	check(SpotifyS.fail_hold(404, true) == 600 and SpotifyS.fail_hold(403, true) == 600 and SpotifyS.fail_hold(429, true) == 0
			and SpotifyS.fail_hold(403, false) == 0 and SpotifyS.fail_hold(404, true, true) == 0, "abgelehnte interne Wege kommen eine Weile aus dem Gedächtnis")
	var msrc := Quelle.lesen("res://src/core/music_spotify.gd")
	check(msrc.contains("if _pf_off != \"\":\n\t\treturn { \"ok\": false, \"code\": 403"), "pathfinder nach 403 für die Anmeldung aus")
	check(msrc.contains("while _api_busy >= API_SLOTS") and msrc.contains("if _inflight.has(key)"), "Lesen gebündelt und begrenzt")
	check(SpotifyEigen.valid_id("0123456789abcdef0123456789ABCDEF") and not SpotifyEigen.valid_id("123") and not SpotifyEigen.valid_id("g123456789abcdef0123456789abcdef"),
			"Spotify-Client-ID: 32 Zeichen hexadezimal")
	check(SpotifyEigen.steps_text().contains(SpotifyEigen.REDIRECT) and SpotifyEigen.steps_text().contains("User Management"), "Anleitung nennt Redirect und User Management")
	print("Steam: kurze Sitzung neben Steam am PC")
	check(SteamCMS.session_allowed("Authentication.GenerateAccessTokenForApp#1", 0, 1000), "Web-Zugang: erste kurze Sitzung erlaubt")
	check(not SteamCMS.session_allowed("Player.GetOwnedGames#1", 1000, 1000 + SteamCMS.RARE_GAP_S - 1)
			and SteamCMS.session_allowed("Player.GetOwnedGames#1", 1000, 1000 + SteamCMS.RARE_GAP_S), "höchstens alle zehn Minuten")
	# Neue QR-Anmeldung: Die Sperrzeit der alten gilt nicht (sonst „übersprungen“ gleich danach).
	var cm_src := (load("res://src/core/steam_cm.gd") as GDScript).source_code
	var chat_src := (load("res://src/core/steam_chat.gd") as GDScript).source_code
	check(cm_src.contains("func reset_rare() -> void:\n\t_rare_at.clear()") and chat_src.contains("SteamCM.reset_rare()\n\tSocial.forget_owned()"),
			"QR-Anmeldung: seltene Sitzung gleich wieder erlaubt, gemerkte Spiele vergessen")
	# Gekaufte Spiele werden gemerkt: Bibliothek, gemeinsame Spiele und Profil teilen ein Ergebnis.
	var soc_src := (load("res://src/core/social.gd") as GDScript).source_code
	check(soc_src.contains("now - _owned_at < OWNED_KEEP_S") and soc_src.contains("return _keep_owned(cm)"), "gekaufte Spiele 30 Min. gemerkt")
	var ml_src := (load("res://src/core/music_listen.gd") as GDScript).source_code
	check(ml_src.contains('if app_mode() and str(me.get("id", "")) != "":'), "Spotify: ohne eigene ID kein /user//recently-played")
	check(not SteamCMS.session_allowed("FriendMessages.GetUnreadMessages#1", 0, 1000) and SteamCMS.session_allowed("FriendMessages.SendMessage#1", 0, 1000),
			"Automatisches sonst nie, Selbst-Angestoßenes immer")
	print("SteamGridDB: ein Schlüssel für den ganzen PC")
	var med_src := (load("res://src/core/media.gd") as GDScript).source_code
	check(med_src.contains('var games: Array = scrape_spiele()') and med_src.contains('return str(g.get("source", "")) in ["rom", "disc"]')
			and med_src.contains('return await scrape_all(["sgdb"], replace, sys)'),
			"SteamGridDB holt Bilder (auch Heroes) für Emulator-Spiele, auch von der Disc; Spiele scrapen für alle Spiele")
	var set_src := (load("res://src/ui/sections/settings_spiele.gd") as GDScript).source_code
	check(set_src.contains("func _bilder() -> void:\n\t_cover_row()") and not set_src.contains("Alle Bilder von SteamGridDB holen"),
			"„Cover holen“ vorn in Spiele › Bilder, nicht mehr versteckt")
	check(Sgdb.format_error("0123456789abcdef0123456789abcdef") == "" and Sgdb.format_error(" 0123456789ABCDEF0123456789abcdef ") == "", "Schlüssel: 32 Zeichen hexadezimal")
	check(Sgdb.format_error("") != "" and Sgdb.format_error("abc") != "" and Sgdb.format_error("0123456789abcdef0123456789abcdeg") != "", "falsche Form erkannt")
	check(Sgdb.answer_error(200) == "" and Sgdb.answer_error(401).contains("neuen") and Sgdb.answer_error(0).contains("online"), "Antwort der Testabfrage als Satz")
	check(Profiles.SHARED.has("accounts.sgdb_key") and ConfigS.shared_secret("accounts.sgdb_key") and not ConfigS.shared_secret("accounts.steam_key"),
			"SteamGridDB gilt für alle Profile, Anmeldungen bleiben je Profil")
	var parts := Profiles.split_settings({ "accounts": { "sgdb_key": "k", "steam_key": "s" } })
	check(str((parts[0] as Dictionary).accounts.sgdb_key) == "k" and not ((parts[1] as Dictionary).accounts as Dictionary).has("sgdb_key")
			and str((parts[1] as Dictionary).accounts.steam_key) == "s", "gespeichert im gemeinsamen Stand")
	var k_prof := PackedByteArray(); k_prof.resize(32); k_prof.fill(7)
	var k_pc := PackedByteArray(); k_pc.resize(32); k_pc.fill(9)
	var old_sealed := Vault.seal("schluessel", k_prof)
	check(Vault.open(old_sealed, [k_pc]) == null and str(Vault.open(old_sealed, [k_prof, k_pc])) == "schluessel"
			and str(Vault.open(Vault.seal("schluessel", k_pc), [k_prof, k_pc])) == "schluessel", "alt mit Profil-Schlüssel, neu mit gemeinsamem: beide öffnen")
	var csrc := Quelle.lesen("res://src/core/config.gd")
	check(csrc.contains("_put_path(saved, p, own_shared[p])") and csrc.contains("Vault.open(node, _open_keys())"), "Profil-Schlüssel wird einmalig übernommen, gemeinsamer Tresor öffnet mit")
	check(RegEx.create_from_string("\"[0-9a-f]{32}\"").search(Quelle.lesen("res://src/core/sgdb_konto.gd")) == null, "kein Schlüssel im Code mitgeliefert")

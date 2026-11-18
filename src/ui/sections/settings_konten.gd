extends "res://src/ui/sections/settings_spiele.gd"
## Einstellungen, Schicht über settings_spiele.gd: die Kategorie Konten – Profil, jeder Dienst mit
## eigener Unterseite (Steam, Epic, Discord, Spotify, YouTube, Twitch, Nuvio, RetroAchievements,
## SteamGridDB; Schlüssel am Ende der Unterseite unter „Freiwillig“, keine dritte Ebene),
## Datenschutz und Abmelden.

const Konten := preload("res://src/core/konten.gd")
const Sgdb := preload("res://src/core/sgdb_konto.gd")
const IidbLogin := preload("res://src/ui/layers/iidb_login.gd")


# --- Konten -----------------------------------------------------------------------------

func _konten() -> void:
	# Profile (Roadmap 109): der Name gehört zum Profil (src/ui/layers/profile_edit.gd).
	_head("Profil")
	_action("Dein Profil", "Name, Bild, Farbe, PIN.", str(Config.profile().get("name", "")),
			func() -> void:
		load("res://src/ui/layers/profile_edit.gd").open_for(main, Config.profile_id), "user")
	var np := Config.profile_list().size()
	_action("Profil wechseln", "Uzai startet dafür kurz neu.", U.plural(np, "Profil", "Profile"), func() -> void: main.open_profiles("switch"), "friends")
	_action("Profile verwalten", "", "", func() -> void: main.open_profiles("manage"), "grid")
	_head("Dienste")
	var steam_on := SteamChat.logged_in()
	_more("Steam", "Freunde, Erfolge, Spielzeit, Chat.",
		("Angemeldet als " + SteamChat.account_name()) if steam_on else "Nicht angemeldet", "steam", _steam_page, "ok" if steam_on else "")
	_more("Epic Games", "Alle gekauften Spiele.", Library.epic_account.status_text(), "games", _epic_page, _epic_tone())
	var voice_on := Voice.ready_()
	var dc_t := "Verbunden" if voice_on else ("Nicht eingerichtet" if not Voice.configured() else "Nicht verbunden")
	_more("Discord", "Sprachkanal, Status, Nachrichten.",
		dc_t, "discord", _discord_page, "ok" if voice_on else ("faint" if not Voice.configured() else ""))
	var mode := str(Config.get_value("system.music_mode", "lokal"))
	var sp_t := "Verbunden" if Music.has_spotify() else "Nicht verbunden"
	if mode != "spotify":
		# Kurz, damit es in die Zeile passt; mehr steht in der Erklärung.
		sp_t = "Aus · " + str({ "tasten": "Musik-Apps", "lokal": "Eigene Dateien" }.get(mode, "Aus")) if mode in ["tasten", "lokal"] else "Aus"
	_more("Spotify", "Bibliothek vom PC, Läuft gerade, Geräte." if Music.grundmodus() else "Playlists, Mixe, Suche.",
		sp_t, "music", _spotify_page, "ok" if Music.has_spotify() and mode == "spotify" else "faint" if mode != "spotify" else "")
	var yt_t: String = YouTube.account if YouTube.logged_in() else ("TV-Anmeldung" if YouTube.tv.logged_in() else "Nicht angemeldet")
	_more("YouTube", "Abos, Playlists, Startseite.",
		yt_t, "video", _youtube_page, "ok" if YouTube.logged_in() or YouTube.tv.logged_in() else "")
	_more("Twitch", "Deine Kanäle, die gerade live sind.",
		Twitch.status_text(), "live", _twitch_page, "ok" if Twitch.state == "bereit" and Twitch.logged_in()
			else ("warn" if Twitch.state in ["abgelaufen", "fehler"] else ""))
	_more("Nuvio", "Addons, Bibliothek, Weiterschauen.",
		NuvioSync.email() if NuvioSync.connected() else "Nicht angemeldet", "qr", _nuvio_rows, "ok" if NuvioSync.connected() else "")
	var ra := str(Config.get_value("accounts.ra_user", ""))
	_more("RetroAchievements", "Erfolge für Emulator-Spiele.",
		ra if ra != "" else "Nicht eingetragen", "retro", _ra_page, "ok" if ra != "" else "")
	var sg_on := Sgdb.connected()
	_more("SteamGridDB", "Cover, Hintergründe, Schriftzüge.", "Verbunden" if sg_on else "Nicht verbunden", "image", _sgdb_page, "ok" if sg_on else "")
	var ii_on: bool = Media.iidb.verbunden()
	_more("iiDB", "Bilder und Spielklang von iiSU.", "Verbunden" if ii_on else "Nicht verbunden", "image", _iidb_page, "ok" if ii_on else "")
	_head("Datenschutz")
	var n := Konten.stored_count(Config.get_value)
	_more("Gespeichert und gesendet", "Je Dienst, mit Abmelden.",
		U.plural(n, "Dienst angemeldet", "Dienste angemeldet") if n > 0 else "Nichts gespeichert", "lock", _privacy_page)


## RetroAchievements: per Handy verbinden, Name und Schlüssel, Abmelden.
func _ra_page() -> void:
	var ra := str(Config.get_value("accounts.ra_user", ""))
	_action("Mit dem Handy verbinden" if ra == "" else "Neu verbinden", "", "QR-Code", func() -> void: main.open_ra_login(), "qr", "accent" if ra == "" else "")
	_text("accounts.ra_user", "Benutzername", "")
	_text("accounts.ra_key", "Web-API-Schlüssel", "retroachievements.org → Einstellungen → Keys.", true)
	if Konten.stored("retroachievements", Config.get_value):
		_action("Abmelden", "", "", func() -> void: _confirm_logout("retroachievements"), "close")


## SteamGridDB: ein Schlüssel für den ganzen PC (übers Handy, sofort geprüft), gilt für alle Profile.
func _sgdb_page() -> void:
	var sg_on := Sgdb.connected()
	_action("Neu verbinden" if sg_on else "Verbinden", "Gilt für alle Profile.", "Verbunden" if sg_on else "Einrichten", func() -> void:
			var l = load("res://src/ui/layers/sgdb_login.gd").new()
			l.main = main
			main.open_layer(l)
			l.closed.connect(func() -> void:
				if is_inside_tree():
					_rebuild_keep()
			, CONNECT_DEFERRED)
	, "image", "ok" if sg_on else "accent")
	_text("accounts.sgdb_key", "Schlüssel", "Kostenlos auf steamgriddb.com.", true)
	if sg_on:
		_action("Schlüssel löschen", "", "", func() -> void: _confirm_logout("steamgriddb"), "close")


## iiDB (iiSU): der eigene Schlüssel, übers Handy oder eingetippt, sofort geprüft; gilt für alle
## Profile. Kein freies Schlüsselfeld – nur ein geprüfter Schlüssel wird gespeichert.
func _iidb_page() -> void:
	var an: bool = Media.iidb.verbunden()
	_action("Neu verbinden" if an else "Verbinden", "Eigener Schlüssel von accounts.iisu.network. Gilt für alle Profile.", "Verbunden" if an else "Einrichten",
			func() -> void:
				var l := IidbLogin.new()
				l.main = main
				main.open_layer(l)
				l.closed.connect(func() -> void:
					if is_inside_tree():
						_rebuild_keep()
				, CONNECT_DEFERRED)
	, "image", "ok" if an else "accent")
	if not an:
		return
	var stufe := IidbLogin.stufe_text(Media.iidb.zugang)
	_action("Stufe", "Wie oft Uzai bei iiDB fragen darf, legt iiDB fest.", stufe if stufe != "" else "Abfragen", func() -> void:
		await Media.iidb.zugang_holen()
		if is_inside_tree():
			_rebuild_keep()
	, "refresh")
	_toggle("library.spielklang", "Spielklang auf der Spielseite", "Der Klang des Spiels von iiDB läuft, solange die Spielseite offen ist.")
	_action("Schlüssel löschen", "", "", func() -> void: _confirm_logout("iidb"), "close")


## Datenschutz (Punkte 13, 77): je Dienst, was gespeichert ist und wohin Uzai spricht (aus
## src/core/konten.gd), und Abmelden, das wirklich alles zur Anmeldung vergisst.
func _privacy_page() -> void:
	# Der eine Satz dieser Seite – als Text oben, nicht als Zeile, die wie eine Einstellung aussieht.
	if _sheet != null and _sheet.has_method("add_label"):
		_sheet.add_label("Keine Telemetrie.", "s", "muted")
		_sheet.add_gap(6)
	_vault_row()
	_head("Dienste")
	var ss_zugang := Screenscraper.zugang().has("devid")
	for s in Konten.SERVICES:
		var id := str(s.id)
		var on := Konten.stored(id, Config.get_value)
		if not on and not angeboten(id, ss_zugang):
			continue
		_action(str(s.name), "Gespeichert: %s Verbindungen: %s" % [s.stores, s.talks], ("Eingetragen" if Konten.key_only(id) else "Angemeldet") if on
				else "Nichts gespeichert",
			func() -> void: _service_tap(id), str(s.icon), "ok" if on else "faint")
	if Konten.stored_count(Config.get_value) > 1:
		_action("Überall abmelden", "", "",
				func() -> void: _confirm_logout(""), "close", "warn")


## Steht der Dienst in diesem Uzai zur Wahl? ScreenScraper braucht den Programmzugang; öffentliche Pakete haben ihn
## nicht (tools/build_windows.sh), dann taucht es auch hier nicht auf – wie überall sonst (screenscraper.gd).
static func angeboten(id: String, ss_zugang: bool) -> bool:
	return id != "screenscraper" or ss_zugang


## Wie Uzai Anmeldungen auf diesem PC schützt (Tresor, src/core/vault.gd).
func _vault_row() -> void:
	var vault := Config.vault_state()
	var vrow = _info_row("Anmeldungen", {
		"dpapi": "Gebunden an dein Windows-Konto (DPAPI).",
		"test": "Testbetrieb: der Schlüssel liegt offen im Datenordner.",
	}.get(vault, "Schutz nicht verfügbar. Nach einem Neustart erneut."), "Verschlüsselt" if vault == "dpapi" else ("Testbetrieb" if vault == "test" else "Nicht verschlüsselt"), "lock")
	vrow.set("tone", "ok" if vault == "dpapi" else "warn")


## Dienst in der Übersicht gewählt: angemeldet → abmelden, sonst dorthin, wo man sich verbindet.
func _service_tap(id: String) -> void:
	var s := Konten.find(id)
	if Konten.stored(id, Config.get_value):
		_confirm_logout(id)
	elif str(s.page) == "Filme-Quellen":
		# Plex, Jellyfin, Emby, Stremio verbinden sich an einer Stelle: Medien → Filme-Quellen.
		main.open_movie_sources()
	elif str(s.page) != "":
		open_more(str(s.page))
	else:
		var path: String = (s.keys as Array)[0]
		_edit_text(path, "%s-Schlüssel" % str(s.name), true)


## Abmelden mit Rückfrage. id "" = bei allen Diensten.
func _confirm_logout(id: String) -> void:
	var name := str(Konten.find(id).get("name", ""))
	var app := id != "" and Konten.has_app(id, Config.get_value)
	var key := id != "" and Konten.key_only(id)
	var head := "Überall abmelden?"
	var text := "Alle Anmeldungen und Schlüssel werden gelöscht. Spiele und Einstellungen bleiben."
	if key:
		head = "%s-Schlüssel löschen?" % name
		text = "Der Schlüssel für %s wird gelöscht. Geladene Bilder bleiben." % name
	elif id != "":
		head = "Von %s abmelden?" % name
		text = "Die Anmeldung bei %s wird gelöscht. Spiele und Einstellungen bleiben." % name
	if app:
		text += " „Auch die eigene App“ löscht deine Entwickler-App mit."
	var buttons: Array = [["Löschen" if key else "Abmelden", func() -> void: _logout(id, false), "danger"]]
	if app:
		buttons.append(["Auch die eigene App", func() -> void: _logout(id, true), "danger"])
	buttons.append(["Abbrechen", func() -> void: pass])
	main.open_dialog(head, text, buttons, "lock" if key else "user", "warn")


## Erst beim Dienst abmelden (Zugang zurückgeben, Verbindung schließen), dann alles zur Anmeldung
## leeren – auch, was der Dienst selbst nicht wegräumt.
func _logout(id: String, with_app: bool) -> void:
	var ids: Array = [id] if id != "" else Konten.SERVICES.map(func(s: Dictionary) -> String: return str(s.id)).filter(
			func(i: String) -> bool: return Konten.stored(i, Config.get_value))
	for sid in ids:
		match sid:
			"steam":
				if SteamChat.logged_in():
					SteamChat.logout()
			"epic":
				Library.epic_account.logout()
			"discord":
				Voice.stop()
			"spotify":
				Music.disconnect_spotify("app")
				Music.disconnect_spotify("eigen")
			"youtube":
				if YouTube.logged_in():
					YouTube.logout()
				if YouTube.tv.logged_in():
					YouTube.tv.logout()
			"twitch":
				Twitch.logout()
			"nuvio":
				if NuvioSync.connected():
					await NuvioSync.logout()
			"plex", "jellyfin", "emby", "stremio":
				await Quellen.logout(str(sid))
		Konten.forget(str(sid), Config.set_value, with_app)
		if str(sid) in ["plex", "jellyfin", "emby", "stremio"]:
			Quellen.forgotten(str(sid))
		match sid:
			"epic":
				Library.refresh_epic()
			"discord":
				Voice.start()
				DiscordChat.restart()
	Config.save_settings()
	var done := "Überall abgemeldet"
	if id != "":
		done = ("%s-Schlüssel gelöscht" if Konten.key_only(id) else "Von %s abgemeldet") % str(Konten.find(id).name)
	Toasts.show_toast(done, "Uzai hat die Anmeldedaten vergessen.", "check")
	if is_inside_tree():
		_rebuild_keep()


func _steam_page() -> void:
	var chat_on := SteamChat.logged_in()
	_action("Von Steam abmelden" if chat_on else "Mit Steam anmelden", "Per QR-Code mit der Steam-App.",
		("Angemeldet: " + SteamChat.account_name()) if chat_on else "QR-Code", func() -> void:
			if SteamChat.logged_in():
				_abmelden_fragen("Steam", func() -> void:
					SteamChat.logout()
					_rebuild_keep())
				return
			main.open_chat({ "id": "", "name": "Steam" }, true)
	, "steam", "ok" if chat_on else "")
	if chat_on and not SteamChat.can_send():
		_action("Senden freischalten", "Einmal neu per QR-Code bestätigen.",
			"QR-Code", func() -> void: main.open_chat({ "id": "", "name": "Steam" }, true), "chat", "warn")
	# Ob der Status gerade wirklich ankommt, steht leise unter dem Schalter.
	var gs := SteamChat.game_status()
	var st_toggle := _toggle_def("steam.status_nonsteam", "Emulator-Spiele bei Steam anzeigen", str(gs.text), true)
	st_toggle.set("subtitle", str(gs.short))
	var iw: WeakRef = weakref(st_toggle)
	st_toggle.connect("changed", func(_v: Variant) -> void:
		var row = iw.get_ref()
		if row:
			row.set("subtitle", str(SteamChat.game_status().short))
	)
	# Schlüssel und Steam-ID nur freiwillig: Die QR-Anmeldung bringt alles mit.
	_head("Freiwillig")
	_text("accounts.steam_key", "Steam-Web-API-Schlüssel", "Nur ohne QR-Anmeldung nötig.", true)
	_text("accounts.steam_id", "Steam-ID", "SteamID64 oder der Name aus steamcommunity.com/id/…")


func _spotify_page() -> void:
	if str(Config.get_value("system.music_mode", "lokal")) != "spotify":
		var eigene := str(Config.get_value("music.local_dir", "")) != ""
		_action("Spotify mit Playlists einschalten", "Deine eigene Musik bleibt daneben." if eigene else "Stellt die Musikquelle (Klang) auf Spotify.", "", func() -> void:
			Config.set_value("system.music_mode", "spotify")
			_rebuild_keep()
		, "music", "accent")
		return
	var app_on := Music.app_ready()
	var own_on := Music.own_ready()
	var using := Music.login_mode()
	# „Mit Spotify anmelden“ (Standard): die echte Anmeldeseite im Uzai-Browser, danach die Spotify-Sitzung
	# (src/core/spotify_web.gd). Abmelden löscht auch den Ordner der Sitzung.
	_head("Spotify")
	if app_on:
		var desc := str(Music.me.get("name", ""))
		if Music.grundmodus():
			desc = "Läuft gerade, Steuern, Geräte und Verlauf."
		elif Music.app_note != "":
			desc = "Zuletzt: " + Music.app_note
		_action("Abmelden", desc, "Wird benutzt" if using == "app" else "Angemeldet", func() -> void:
			_abmelden_fragen("Spotify", func() -> void:
				Music.disconnect_spotify("app")
				_rebuild_keep())
		, "user", "ok" if using == "app" else "")
	else:
		var desc2 := "Einmal mit deinem Spotify-Konto."
		if Music.app_note != "":
			desc2 = Music.app_note
		_action("Mit Spotify anmelden", desc2, "", func() -> void:
			load("res://src/ui/layers/spotify_anmelden.gd").start(main, func(_err: String) -> void:
				if is_inside_tree():
					_rebuild_keep()
			)
		, "music", "warn" if Music.app_note != "" else "accent")
	# Eigene Spotify-App: der zweite Weg (Web-API mit eigener Client-ID). Eingerichtet steht sie hier,
	# sonst unter „Weitere Optionen“.
	var profi := own_on or str(Config.get_value("accounts.spotify_client_id", "")) != ""
	var connected := own_on
	var spotify_action := func() -> void:
		if connected:
			_abmelden_fragen("Spotify", func() -> void:
				Music.disconnect_spotify("eigen")
				_rebuild_keep())
			return
		if str(Config.get_value("accounts.spotify_client_id", "")) == "":
			# Schritt für Schritt, Client-ID übers Handy (src/ui/layers/spotify_eigen.gd).
			load("res://src/ui/layers/spotify_eigen.gd").start(main, func(_err: String) -> void:
				if is_inside_tree():
					_rebuild_keep()
			)
			return
		# Spotify erlaubt die Anmeldung nur im Browser. Uzai sagt das vorher und öffnet ihn erst auf Wunsch.
		main.open_dialog("Mit Spotify verbinden", "Im Browser am PC bestätigen.", [
			["Browser öffnen", func() -> void: _connect_spotify()],
			["Später", func() -> void: pass],
		])
	var sp_state := ("Wird benutzt" if using == "eigen" else "Verbunden") if connected else ""
	var sp_tone := "ok" if connected and using == "eigen" else ""
	if connected and using == "eigen" and Music.problem != "":
		sp_state = str(
				{ "nutzer": "Konto nicht in der App", "premium": "App gesperrt", "abgelaufen": "Abgelaufen", "gesperrt": "Konto abgelehnt" }.get(Music.problem, "Fehler"))
		sp_tone = "warn"
	if profi:
		_head("Eigene Spotify-App")
		_action("Eigene App trennen" if connected else "Mit eigener App verbinden",
				"Einmal im Browser am PC bestätigen." + ((" " + Music.problem_text(Music.problem))
				if connected and using == "eigen" and Music.problem != "" else ""),
			sp_state, spotify_action, "link", sp_tone)
	if app_on and own_on:
		_action("Benutzen", "",
				"Spotify-Anmeldung" if using == "app" else "Eigene Spotify-App", func() -> void:
			Config.set_value("accounts.spotify_mode", "eigen" if using == "app" else "app")
			_rebuild_keep()
		, "repeat")
	# Eigener Verlauf: nur auf diesem PC, für „Zuletzt gehört“, „Oft gehört“ und die Musik-Kachel.
	_head("Verlauf")
	_toggle_def("music.verlauf", "Verlauf merken", "Nur auf diesem PC.", true)
	var n_v := Music.verlauf_list().size()
	_action("Verlauf löschen", U.plural(n_v, "Eintrag", "Einträge") if n_v > 0 else "Leer", "", _verlauf_loeschen, "history")
	if Music.has_spotify():
		_action("Verbindung prüfen", "", "", func() -> void:
			main.open_layer(load("res://src/ui/layers/spotify_check.gd").new()), "search")
	_head("Weitere Optionen")
	if not profi:
		_action("Eigene Spotify-App", "Etwa zwei Minuten. Spotify Premium nötig.", "", spotify_action, "link")
	_text("accounts.spotify_client_id", "Spotify-Client-ID", "developer.spotify.com, Redirect http://127.0.0.1:8888/callback.")


## Eigenen Musik-Verlauf löschen (nach Rückfrage).
func _verlauf_loeschen() -> void:
	var weg := func() -> void:
		Music.verlauf_clear()
		Toasts.show_toast("Verlauf gelöscht", "", "history", { "ms": 1600, "quiet": true })
		if is_inside_tree():
			_rebuild_keep()
	main.open_dialog("Verlauf löschen?", "Gespeicherte Musikdaten werden gelöscht. Spotify bleibt unverändert.",
			[["Löschen", weg], ["Abbrechen", func() -> void: pass]], "history", "warn")


func _discord_page() -> void:
	var vstate := { "aus": "Nicht eingerichtet", "verbinde": "Verbindet …", "anmelden": "In Discord bestätigen", "getrennt": "Noch nicht freigegeben",
			"bereit": "Verbunden", "fehler": "Fehler" }
	var vtone := { "aus": "faint", "bereit": "ok", "fehler": "warn", "anmelden": "accent" }
	var voice_action := func() -> void:
		if Voice.ready_():
			_abmelden_fragen("Discord", func() -> void:
				Voice.stop()
				Config.set_value("accounts.discord_token", "")
				Config.set_value("accounts.discord_refresh", "")
				Voice.start()
				_rebuild_keep())
			return
		if not Voice.configured():
			Toasts.show_toast("Discord geht gerade nicht", Voice.missing_text(), "discord", { "ms": 6000 })
			return
		# Schritt für Schritt sichtbar: wo es hängt, steht dort mit dem Grund von Discord.
		main.open_layer(load("res://src/ui/layers/discord_connect.gd").new())
	_voice_shown = "%s|%s|%s|%s" % [Voice.state, Voice.error, DiscordChat.state, DiscordChat.error]
	var vdesc := "Einmal in der Discord-App bestätigen." if Voice.uzai_app_direkt() else "Eigene Discord-App, etwa 3 Minuten mit dem Handy."
	var problem := Voice.setup_problem()
	if problem != "":
		vdesc = problem
	if Voice.error != "":
		vdesc = "Zuletzt: " + Voice.error
	var vrow = _action("Freigabe zurücknehmen" if Voice.ready_() else "Mit Discord verbinden", vdesc, str(vstate.get(Voice.state, Voice.state)), voice_action,
			"headset", str(vtone.get(Voice.state, "")))
	# Freigeschaltete Konten (Tester von Uzais App) ohne Merker: langes A versucht es mit Uzais App. Bewusst ohne
	# sichtbare Zeile – alle anderen sollen gleich den Weg zur eigenen App sehen (discord_connect.gd).
	if not Voice.ready_() and Voice.configured() and Voice.builtin() and vrow is Control:
		(vrow as Control).set_meta("uz_on_hold_a", func() -> void:
			var l = load("res://src/ui/layers/discord_connect.gd").new()
			l.uzai_app = true
			main.open_layer(l))
	# Uzais App ist für dieses Konto nicht freigeschaltet: der Weg dorthin gleich darunter, nicht erst unter „Eigene App“.
	if Voice.tester_fehlt and Voice.builtin():
		_action("Volle Discord-Steuerung einrichten", "Eigene Discord-App, etwa 3 Minuten mit dem Handy.", "", _eigene_app, "discord", "accent")
	_toggle("accounts.discord_voice", "Sprachkanal im Guide", "")
	_toggle("accounts.discord_presence", "Status „Spielt … auf Uzai“", "Einzelne Spiele: in ihren Optionen.")
	var servers: Array = Config.get_value("accounts.discord_servers", [])
	var set_servers := func(v: String) -> void:
		var out: Array = []
		for part in v.split(","):
			if part.strip_edges() != "":
				out.append(part.strip_edges())
		Config.set_value("accounts.discord_servers", out)
		Social.refresh_discord()
		_rebuild_keep()
	var edit_servers := func() -> void:
		main.open_keyboard("Server-IDs, mit Komma getrennt", ", ".join(PackedStringArray(servers)), set_servers)
	var srow := _action("Server", "Server-IDs, mit Komma. Das Widget des Servers muss an sein.",
		U.plural(servers.size(), "Server", "Server") if not servers.is_empty() else "Keine", edit_servers, "discord", "faint" if servers.is_empty() else "")
	srow.set_meta("uz_path", "accounts.discord_servers")
	# Wer aus Discord welcher Steam-Freund ist (Guide → Discord → „Alle im Call zu Remote Play einladen“).
	var nmap: int = load("res://src/core/call_invite.gd").load_map().size()
	_action("Zuordnungen Discord ↔ Steam", "Für „Alle im Call zu Remote Play einladen“.",
		U.plural(nmap, "Zuordnung", "Zuordnungen") if nmap > 0 else "Keine", func() -> void:
			var l = load("res://src/ui/layers/call_mappings.gd").new()
			l.main = main
			l.on_change = _rebuild_keep
			main.open_layer(l)
	, "friends", "faint" if nmap == 0 else "")
	_discord_dm_rows()
	# Uzai bringt seine eigene Discord-App mit (Voice.APP_ID). Eine eigene ist freiwillig.
	_head("Eigene Discord-App", "freiwillig")
	_action("Mit dem Handy einrichten", "Für Sprachkanäle, Stummschalten und Streams im Guide. Etwa 3 Minuten.",
		"Eingetragen" if Voice.own_id() != "" else "", _eigene_app, "discord", "ok" if Voice.own_id() != "" else "")
	_text("accounts.discord_client_id", "Eigene App-ID", "discord.com/developers: OAuth2 → „Public Client“ an, Redirects http://localhost und http://127.0.0.1/callback.")
	_text("accounts.discord_client_secret", "Client-Secret", "Nur ohne „Public Client“. Nicht den Bot-Token.", true)


## „Volle Discord-Steuerung“: eigene Discord-App mit dem Handy anlegen und eintragen (discord_eigen.gd).
func _eigene_app() -> void:
	main.open_layer(load("res://src/ui/layers/discord_eigen.gd").new())


## Discord-Direktnachrichten über das offizielle Discord Social SDK (gleiche App wie oben).
func _discord_dm_rows() -> void:
	_head("Nachrichten")
	_toggle("accounts.discord_dm", "Discord-Nachrichten in Uzai", "Über Discords offizielles Social SDK.")
	var desc := ""
	if DiscordChat.error != "" and DiscordChat.state != "bereit":
		desc = "Zuletzt: " + DiscordChat.error
	var tone := { "bereit": "ok", "fehler": "warn", "keine_dll": "warn", "freigabe": "accent" }
	# „fehler“ verbindet neu (unten restart), nur „freigabe“ fragt Discord nach der Freigabe.
	_action("Nachrichten freigeben" if DiscordChat.state == "freigabe" else ("Neu verbinden" if DiscordChat.state in ["bereit", "fehler"] else "Prüfen"), desc,
		DiscordChat.status_text(), func() -> void:
			if DiscordChat.state == "freigabe":
				DiscordChat.authorize()
				Toasts.show_toast("Bitte in Discord bestätigen", "Danach geht es hier weiter.", "discord")
			else:
				DiscordChat.restart()
				Toasts.show_toast("Discord-Nachrichten", "Verbinde neu …", "discord", { "quiet": true })
			_rebuild_keep()
	, "chat", str(tone.get(DiscordChat.state, "")))
	if DiscordChat.state in ["freigabe", "fehler"] and Voice.extra_rejected:
		_action("Im Browser freigeben", "Die Discord-App hat abgelehnt.", "Einmalig",
				func() -> void:
			DiscordChat.authorize_browser()
		, "discord")


func _youtube_page() -> void:
	if YouTube.logged_in():
		_action("Abmelden", "Eigene Uzai-Abos bleiben.", YouTube.account,
				func() -> void:
			_abmelden_fragen("YouTube", func() -> void:
				YouTube.logout()
				_rebuild_keep())
		, "user", "text")
		_action("Abos neu abgleichen", "", "", func() -> void:
			await YouTube.import_subscriptions()
			Toasts.show_toast("Abos abgeglichen", U.plural((YouTube.data.subs as Array).size(), "Kanal", "Kanäle"), "check")
		, "refresh")
	else:
		_action("Mit Google anmelden", "Abos, Playlists und „Mag ich“.", "QR-Code", func() -> void: main.open_yt_login(), "qr")
	_action("Google-Zugang", "Einmalig, die Anmeldung führt durch.",
		"Eingerichtet" if YouTube.has_client() else "Fehlt", func() -> void: main.open_yt_login(), "lock", "ok" if YouTube.has_client() else "warn")
	_youtube_tv_rows()


## Twitch (Streams): Anmeldung wie die Twitch-App am Fernseher (inoffiziell) oder offiziell mit
## eigener Client-ID; Sprache der Reihe „Beliebt auf …“.
func _twitch_page() -> void:
	var tone := "ok" if Twitch.state == "bereit" else ("warn" if Twitch.state in ["fehler", "abgelaufen"] else "")
	var reopen := func() -> void:
		var l: Control = main.open_twitch_login()
		l.closed.connect(func() -> void:
			if is_inside_tree():
				_rebuild_keep()
		, CONNECT_DEFERRED)
	if Twitch.logged_in():
		var desc := ""
		if str(Twitch.followed_error) != "":
			desc = "Zuletzt: " + str(Twitch.followed_error)
		_action("Abmelden", desc, Twitch.status_text(), func() -> void:
			_abmelden_fragen("Twitch", func() -> void:
				Twitch.logout()
				_rebuild_keep())
		, "user", tone)
		_action("Gefolgte neu laden", "", "", func() -> void:
			await Twitch.refresh_followed(true)
			if str(Twitch.followed_error) == "":
				Toasts.show_toast("Gefolgte geladen", U.plural(Twitch.followed.size(), "Kanal", "Kanäle") + " gerade live.", "check")
			else:
				Toasts.show_toast("Nicht geladen", str(Twitch.followed_error), "warning", { "ms": 6000 })
		, "refresh")
	else:
		var desc2 := "Per QR-Code."
		if Twitch.state == "abgelaufen":
			desc2 = "Abgelaufen: einmal neu anmelden."
		_action("Mit Twitch anmelden", desc2, Twitch.status_text() if Twitch.state == "abgelaufen" else "QR-Code", reopen, "qr", "warn"
				if Twitch.state == "abgelaufen" else "accent")
	_head("Streams")
	_choice("twitch.lang", "Sprache der Reihe „Beliebt“", "",
			[["DE", "Deutsch"], ["EN", "Englisch"], ["FR", "Französisch"], ["ES", "Spanisch"], ["IT", "Italienisch"]])
	_head("Freiwillig")
	var own := Twitch.own_client()
	_action("Eigene Client-ID", "dev.twitch.tv/console, Typ „Öffentlich“, Redirect http://localhost.",
		own.left(8) + "…" if own != "" else "Nicht eingetragen", func() -> void:
			main.open_keyboard("Twitch-Client-ID", own, func(cid: String) -> void:
				Config.set_value("accounts.twitch_client_id", cid.strip_edges())
				Config.set_value("accounts.twitch_mode", "eigen" if cid.strip_edges() != "" else "")
				_rebuild_keep()
			, false, str(KEY_LINKS.get("accounts.twitch_client_id", "")))
	, "lock", "ok" if own != "" else "").set_meta("uz_path", "accounts.twitch_client_id")
	if own != "":
		_choice("accounts.twitch_mode", "Anmelden mit", "Gilt ab der nächsten Anmeldung.",
				[["", "Standard"], ["eigen", "Eigene Client-ID"]])


## YouTube wie auf dem Fernseher (auf Wunsch, inoffiziell): echte Startseite und Empfehlungen.
func _youtube_tv_rows() -> void:
	var tv = YouTube.tv
	_head("TV-Anmeldung")
	var tone := "ok" if tv.state == "bereit" else ("warn" if tv.state in ["fehler", "abgelaufen"] else "")
	if tv.logged_in():
		var desc := ""
		if str(tv.home_error) != "":
			desc = "Zuletzt: " + str(tv.home_error)
		_action("Abmelden", desc, tv.status_text(), func() -> void:
			_abmelden_fragen("YouTube", func() -> void:
				tv.logout()
				_rebuild_keep())
		, "user", tone)
		_action("Startseite neu laden", "", "", func() -> void:
			await tv.refresh_home(true)
			if str(tv.home_error) == "":
				Toasts.show_toast("Startseite geladen", U.plural(tv.shelves.size(), "Reihe", "Reihen") + " von YouTube.", "check")
			else:
				Toasts.show_toast("Startseite nicht geladen", str(tv.home_error), "warning", { "ms": 6000 })
		, "refresh")
		_toggle("youtube.tv_history", "Gesehenes an YouTube melden", "")
	else:
		var desc2 := "Deine YouTube-Startseite."
		if tv.state == "abgelaufen":
			desc2 = "Abgelaufen: einmal neu anmelden."
		_action("Mit TV-Code anmelden", desc2, tv.status_text() if tv.state == "abgelaufen" else "QR-Code", func() -> void:
			var l = main.open_layer(load("res://src/ui/layers/yt_tv_login.gd").new())
			l.closed.connect(func() -> void:
				if is_inside_tree():
					_rebuild_keep()
			, CONNECT_DEFERRED)
		, "qr", "warn" if tv.state == "abgelaufen" else "accent")


# --- Nuvio ---------------------------------------------------------------------

## Nuvio-Konto: anmelden, Profil, abgleichen, abmelden.
func _nuvio_rows() -> void:
	if not NuvioSync.connected():
		_action("Mit Nuvio anmelden", "Per QR-Code, wie in der Nuvio-TV-App.", "QR-Code", func() -> void: main.open_nuvio_login(), "qr", "accent")
		return
	var profs := NuvioSync.profiles()
	if profs.size() > 1:
		var opts: Array = profs.map(func(p): return [int(p.get("profile_index", 1)), str(p.get("name", "Profil %d" % int(p.get("profile_index", 1))))])
		_action("Profil", "", NuvioSync.profile_name(), func() -> void:
			main.open_choice("Nuvio-Profil", opts, NuvioSync.profile_id(), func(v: Variant) -> void:
				NuvioSync.set_profile(int(v))
				_rebuild_keep()
			)
		, "user")
	# Der Zustand des Kontos steht an dieser Zeile.
	var sync_row := _action("Jetzt abgleichen",
			("Letzter Fehler: " + NuvioSync.last_error) if NuvioSync.last_error != "" else (("Noch %d Änderungen warten aufs Senden." % NuvioSync.pending_count())
			if NuvioSync.pending_count() > 0 else "Auch beim Start und alle 10 Minuten."),
			NuvioSync.status_text(), func() -> void:
		Toasts.show_toast("Nuvio wird abgeglichen …", NuvioSync.email(), "refresh", { "ms": 2000, "quiet": true })
		var err := await NuvioSync.sync(true)
		if err == "":
			Toasts.show_toast("Nuvio abgeglichen", "Abgeglichen.", "check", { "sound": "select" })
		else:
			Toasts.show_toast("Abgleich ging nicht", err, "warning", { "ms": 7000 })
		_rebuild_keep()
	, "refresh", "ok" if NuvioSync.last_error == "" else "warn")
	sync_row.set_meta("uz_key", "nuvio:sync")
	_action("Abmelden", "", "",
			func() -> void:
		_abmelden_fragen("Nuvio", func() -> void:
			await NuvioSync.logout()
			Toasts.show_toast("Von Nuvio abgemeldet", "", "check")
			_rebuild_keep())
	, "close")

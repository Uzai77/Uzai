extends Node
## Anmelde-Ebenen und ihre Zustände (src/core/zustand.gd, docs/ZUSTAENDE.md): Jede Ebene, die von yt_login.gd erbt,
## setzt nur Zustände der gemeinsamen Tabelle „anmeldung.code“ (tools/zustaende.py liest nur yt_login.gd selbst),
## die Eingabe-Anmeldungen (Epic, RetroAchievements, SteamGridDB) nur die aus konten.gd; geht eine Ebene zu, ist ihr
## Stand aus Zustand.lage() weg (kein alter Stand im Fehlerbericht). Dazu Nuvio: „E-Mail und Passwort“ hält den
## QR-Code nicht an, solange nichts abgeschickt ist; Jellyfin: hinter der Tastatur steht eine Seite mit Knöpfen;
## Stremio und Plex: „Nochmal versuchen“ lädt nach einem Netzfehler nur neu; Discord-Nachrichten: „Verbindet …“
## bleibt nicht für immer stehen.
## Aufruf: UZAI_DATA=<leerer ordner> godot --headless --path . res://tests/logic_anmeldung.tscn

const YtLogin := preload("res://src/ui/layers/yt_login.gd")
const Konten := preload("res://src/core/konten.gd")
const Zustand := preload("res://src/core/zustand.gd")
const MedienQ := preload("res://src/core/medienquellen.gd")
const CODE := ["yt_login", "twitch_login", "yt_tv_login", "plex_login", "jellyfin_login", "stremio_login", "nuvio_login"]
const PRUEFEN := ["epic_login", "ra_login", "sgdb_login"]

var fails := 0
var _tastatur: Array = []        ## [Titel, Rückruf] der zuletzt geöffneten Bildschirmtastatur


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_tabellen()
	_vergessen()
	_nuvio_mail()
	_jellyfin_passwort()
	_nochmal()
	await _discord_frist()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Jede Zuweisung _state = "…" in den Ebenen steht in ihrer Tabelle: Tippfehler und neue Zustände fallen hier auf,
## nicht erst als ZUSTAND-VERSTOSS mitten im Ablauf.
func _tabellen() -> void:
	print("Zustände der Anmelde-Ebenen stehen in ihren Tabellen")
	var re := RegEx.create_from_string("(?<![.\\w])_state\\s*=\\s*\"([a-z_]*)\"")
	for f in CODE + PRUEFEN:
		var t: Dictionary = YtLogin.ZUSTAENDE_ANMELDUNG if f in CODE else Konten.ZUSTAENDE_PRUEFEN
		var src := FileAccess.get_file_as_string("res://src/ui/layers/%s.gd" % f)
		var fremd: Array = []
		var n := 0
		for m in re.search_all(src):
			n += 1
			if not t.has(m.get_string(1)):
				fremd.append(m.get_string(1))
		check(n > 0 and fremd.is_empty(), "%s: %d Zuweisungen, alle in der Tabelle%s" % [f, n, (" – fehlt: " + str(fremd)) if not fremd.is_empty() else ""])
	for t in [YtLogin.ZUSTAENDE_ANMELDUNG, Konten.ZUSTAENDE_PRUEFEN]:
		var aus: Array = (t as Dictionary).keys().filter(func(z: String) -> bool: return z != "done" and (t[z] as Array).is_empty())
		check(aus.is_empty(), "jeder Zustand außer „fertig“ hat einen Ausgang %s" % (str(aus) if not aus.is_empty() else ""))


## Geht die Ebene (bzw. die Songtext-Fläche) zu, verschwindet ihr Stand aus Zustand.lage(): Sonst stünde im
## Fehlerbericht ein alter Stand wie „anmeldung.code: wait (seit 40 min)“.
func _vergessen() -> void:
	print("Ebene zu: ihr Stand ist weg aus dem Fehlerbericht")
	var faelle := [["src/ui/layers/stremio_login.gd", "anmeldung.code", "_state", "notice"],
		["src/ui/layers/sgdb_login.gd", "anmeldung.sgdb", "_state", "busy"],
		["src/ui/layers/chat_view.gd", "chat.steam_anmeldung", "_login_state", "start"],
		["src/ui/components/lyrics_panel.gd", "musik.songtext", "", ""]]
	for fall in faelle:
		var n := str(fall[1])
		var l: Node = load("res://" + str(fall[0])).new()
		add_child(l)
		if str(fall[2]) != "":
			l.set(str(fall[2]), str(fall[3]))
		check(_stand(n) != "?", "%s: steht in lage(), solange die Ebene offen ist (%s)" % [n, _stand(n)])
		remove_child(l)
		check(_stand(n) == "?", "%s: Ebene zu – weg aus lage()" % n)
		l.free()


func _stand(name: String) -> String:
	for e in Zustand.lage():
		if str(e.name) == name:
			return str(e.zustand)
	return "?"


## Nuvio: „E-Mail und Passwort“ auf dem QR-Bildschirm. Früher ging der Ablauf sofort in einen eigenen Zustand „mail“:
## Schloss man die Tastatur wieder, stand der QR-Code tot da (keine Abfrage mehr, die Zeit stand still).
func _nuvio_mail() -> void:
	print("Nuvio: der E-Mail-Weg hält den QR-Code nicht an")
	var l = load("res://src/ui/layers/nuvio_login.gd").new()
	l.main = self
	l._state = "wait"
	l._state = "code"
	_tastatur = []
	l._ask_mail()
	check(_tastatur.size() == 2 and str(_tastatur[0]).contains("E-Mail"), "Tastatur für die E-Mail geht auf")
	check(l._state == "code", "der QR-Code gilt weiter, solange nichts abgeschickt ist (%s)" % l._state)
	(_tastatur[1] as Callable).call("ich@example.org")
	check(l._state == "code" and str(_tastatur[0]) == "Passwort", "nach der E-Mail: Passwort, der QR-Code gilt noch")
	l.free()


## Jellyfin/Emby: Hinter der Tastatur für Name und Passwort stand früher eine Seite ohne Knöpfe – wer die Tastatur
## schloss, kam nur mit B weiter (Ebene zu). Jetzt „passwort“ mit „Anmelden“; vom Quick-Connect-Code aus gilt der
## Code weiter, bis das Passwort abgeschickt ist.
func _jellyfin_passwort() -> void:
	print("Jellyfin: Tastatur zu – „Anmelden“ öffnet sie wieder")
	var l = load("res://src/ui/layers/jellyfin_login.gd").new()
	l.main = self
	l._server = { "name": "Wohnzimmer" }
	l._state = "wait"
	_tastatur = []
	l._ask_password()
	check(l._state == "passwort" and _tastatur.size() == 2 and str(_tastatur[0]).contains("Benutzername"),
		"Tastatur für den Namen geht auf, dahinter „passwort“ (%s)" % l._state)
	l.box = VBoxContainer.new()
	l.fill()
	var knoepfe := _knoepfe(l.box)
	check(knoepfe.has("Anmelden") and knoepfe.has("Schließen"), "Tastatur geschlossen: „Anmelden“ und „Schließen“ %s" % str(knoepfe))
	l.box.free()
	l._state = "wait"
	l._state = "code"
	_tastatur = []
	l._ask_password()
	check(l._state == "code" and _tastatur.size() == 2, "vom Quick-Connect-Code aus: der Code gilt weiter (%s)" % l._state)
	l.free()


func _knoepfe(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Button:
			out.append((c as Button).text)
		out += _knoepfe(c)
	return out


## Stremio und Plex: Ging nach der Anmeldung nur das Laden schief (Netz, Server stumm), begann „Nochmal versuchen“
## früher eine neue Anmeldung mit neuem Code. Jetzt wird nur neu geladen; nimmt der Dienst die Anmeldung nicht mehr
## an (401/403), geht es wie bisher von vorn los.
func _nochmal() -> void:
	print("Stremio und Plex: „Nochmal versuchen“ lädt neu, statt neu anzumelden")
	check(MedienQ.abgelaufen({ "code": 401 }) and MedienQ.abgelaufen({ "code": 403 }) and not MedienQ.abgelaufen({ "code": 0 })
		and not MedienQ.abgelaufen({ "code": 503 }), "401/403 heißt abgelaufen, Netz- und Serverfehler nicht")
	var st = load("res://src/ui/layers/stremio_login.gd").new()
	st._state = "wait"
	st._addons_da({ "ok": false, "addons": [], "error": "Stremio: keine Verbindung oder Zeitüberschreitung.", "anmelden": false })
	check(st._state == "error" and st._nochmal == "addons", "Stremio, Netzfehler: Nochmal lädt nur die Addons (%s)" % st._nochmal)
	st._state = "wait"
	st._addons_da({ "ok": false, "addons": [], "error": "Stremio: Anmeldung abgelaufen.", "anmelden": true })
	check(st._nochmal == "anmelden", "Stremio, Anmeldung abgelaufen: Nochmal meldet neu an")
	st.free()
	var px = load("res://src/ui/layers/plex_login.gd").new()
	px._state = "wait"
	px._server_da({ "ok": false, "servers": [], "error": "plex.tv: keine Verbindung oder Zeitüberschreitung.", "anmelden": false })
	check(px._state == "error" and px._nochmal == "server", "Plex, Netzfehler: Nochmal lädt nur die Server (%s)" % px._nochmal)
	px._state = "wait"
	px._server_da({ "ok": true, "servers": [] })
	check(px._state == "error" and px._nochmal == "anmelden", "Plex, kein Server im Konto: wie bisher von vorn")
	px._state = "wait"
	px._server_da({ "ok": false, "servers": [], "error": "plex.tv: Anmeldung abgelaufen.", "anmelden": true })
	check(px._nochmal == "anmelden", "Plex, Anmeldung abgelaufen: Nochmal meldet neu an")
	px.free()


## Discord-Nachrichten: Nahm das SDK den Zugang an und meldete nie „bereit“, stand für immer „Verbindet …“ da.
## Jetzt nach verbinde_secs „fehler“; ein spätes „bereit“ gilt trotzdem, ein Wechsel in der Zeit hebt die Frist auf.
func _discord_frist() -> void:
	print("Discord-Nachrichten: „Verbindet …“ bleibt nicht für immer stehen")
	var keep_runner: Callable = DiscordChat.runner
	var keep_secs := DiscordChat.verbinde_secs
	DiscordChat.verbinde_secs = 0.2
	DiscordChat.runner = func(_cmd: String, _args: Dictionary, _t: float) -> Dictionary:
		return { "ok": true, "result": { "ok": true } }
	Config.set_value("accounts.discord_dm_token", "probe")
	Config.set_value("accounts.discord_dm_expires", int(Time.get_unix_time_from_system()) + 86400)
	DiscordChat._state_to("aus", "")
	await DiscordChat._connect_token()
	check(DiscordChat.state == "verbinde", "Zugang angenommen: verbinde (%s)" % DiscordChat.state)
	await get_tree().create_timer(0.5).timeout
	check(DiscordChat.state == "fehler" and DiscordChat.error != "", "kein „bereit“ vom SDK: nach der Frist fehler (%s)" % DiscordChat.state)
	await DiscordChat._ready_now()
	check(DiscordChat.state == "bereit", "spätes „bereit“ gilt trotzdem (%s)" % DiscordChat.state)
	DiscordChat._state_to("aus", "")
	await DiscordChat._connect_token()
	DiscordChat._state_to("aus", "")
	DiscordChat._state_to("verbinde", "")
	await get_tree().create_timer(0.5).timeout
	check(DiscordChat.state == "verbinde", "neu verbinden in der Zeit: die alte Frist gilt nicht mehr (%s)" % DiscordChat.state)
	# Freigabe im Browser: Meldet das SDK nie zurück (Fenster geschlossen, ohne zu bestätigen), blieb „läuft“ stehen,
	# und der Knopf tat bis zum Neustart nichts mehr.
	var rufe := [0]
	DiscordChat.runner = func(cmd: String, _args: Dictionary, _t: float) -> Dictionary:
		if cmd == "dsdk-authorize":
			rufe[0] += 1
		return { "ok": true, "result": { "ok": true } }
	DiscordChat._started = true
	await DiscordChat.authorize_browser()
	await DiscordChat.authorize_browser()
	check(rufe[0] == 1 and DiscordChat.state == "freigabe", "Freigabe: ein zweiter Druck gleich danach ist derselbe (%d)" % rufe[0])
	DiscordChat._browser_auth_ms -= DiscordChat.FREIGABE_NEU_MS + 1
	await DiscordChat.authorize_browser()
	check(rufe[0] == 2, "Freigabe ohne Rückmeldung des SDK: nach einer halben Minute geht es wieder (%d)" % rufe[0])
	DiscordChat._browser_auth = false
	DiscordChat._started = false
	DiscordChat._state_to("aus", "")
	DiscordChat.runner = keep_runner
	DiscordChat.verbinde_secs = keep_secs
	Config.set_value("accounts.discord_dm_token", "")
	Config.set_value("accounts.discord_dm_expires", 0)


## Wie main.open_keyboard (nur für den Test): merkt sich Titel und Rückruf.
func open_keyboard(head: String, _text: String, cb: Callable, _secret := false, _link := "") -> void:
	_tastatur = [head, cb]

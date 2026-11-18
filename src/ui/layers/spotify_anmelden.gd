extends RefCounted
## „Mit Spotify anmelden“ – überall, wo Uzai Spotify verbindet (leere Bühne, Einrichtung, Einstellungen › Konten,
## Musikbereich, Verbindung prüfen). Öffnet die echte Anmeldeseite von Spotify im Uzai-Browser (browser.gd mit
## spotify = true: eigener Kern-Ordner, nur Spotify, Controller, Uzai-Tastatur). Spotifys eigene Wege dort (Passwort,
## Code per Mail, Passkey) bleiben, wie Spotify sie anbietet. Sobald der Webplayer einen Schlüssel eines Kontos
## meldet, schließt das Fenster von selbst (Music.web_angemeldet). Danach holt die Spotify-Sitzung
## (src/core/spotify_web.gd) Bibliothek, Mixe und Suche; Abspielen geht über Spotify Connect an die Spotify-App am PC.
## Die eigene Spotify-App (spotify_eigen.gd) bleibt der zweite Weg unter Einstellungen › Konten › Spotify.

const Web := preload("res://src/core/spotify_web.gd")
const Main := preload("res://src/main.gd")


## Anmeldeseite öffnen. done bekommt "" bei Erfolg, sonst "abgebrochen" (oder warum es nicht geht).
static func start(main_node: Main, done: Callable = Callable()) -> void:
	if not _browser_da():
		var err := "Im Kinderprofil und im abgesicherten Modus gibt es keine Anmeldeseite." if Config.is_kid() or Config.safe_mode \
				else "Die Anmeldeseite braucht Windows."
		Toasts.show_toast("Spotify nicht verbunden", err, "music")
		if done.is_valid():
			done.call(err)
		return
	Config.set_value("system.music_mode", "spotify")
	var l: Control = load("res://src/ui/layers/browser.gd").new()
	l.set("spotify", true)
	l.set("start_url", Web.ANMELDEN_URL)
	main_node.open_layer(l)
	l.connect("closed", func() -> void:
		if done.is_valid():
			done.call("" if Music.app_ready() or Music.demo() else "abgebrochen")
	, CONNECT_DEFERRED)


## Neu anmelden, wo auch immer Uzai danach fragt: mit eigener Client-ID (gerade benutzt) wie bisher im Browser am
## PC, sonst „Mit Spotify anmelden“. done bekommt "" bei Erfolg.
static func relogin(main_node: Main, done: Callable = Callable()) -> void:
	if Music.login_mode() == "eigen":
		Toasts.show_toast("Spotify-Anmeldung", "Im Browser bestätigen.", "music", { "ms": 6000 })
		var err: String = await Music.connect_spotify()
		if err != "":
			Toasts.show_toast("Spotify nicht verbunden", err, "warning")
		if done.is_valid():
			done.call(err)
		return
	start(main_node, done)


static func _browser_da() -> bool:
	return (OS.get_name() == "Windows" or Music.demo()) and not Config.safe_mode and not Config.is_kid()

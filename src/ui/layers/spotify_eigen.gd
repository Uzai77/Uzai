extends RefCounted
## Eigene Spotify-App, Schritt für Schritt (etwa zwei Minuten, einmalig): der verlässliche Weg,
## wenn Spotify die Anmeldung wie die Spotify-App blockiert (pathfinder 403, Web-API 429).
## Dashboard-Link und Client-ID gehen übers Handy (Tastatur mit Handy-Seite), danach bestätigt
## Spotify einmal im Browser am PC. Aufruf: SpotifyEigen.start(main, done) – done bekommt "" bei Erfolg.

const Main := preload("res://src/main.gd")

const DASHBOARD := "https://developer.spotify.com/dashboard"
const REDIRECT := "http://127.0.0.1:8888/callback"


## Die Schritte als Text (auch für Tests).
static func steps_text() -> String:
	return "1. developer.spotify.com/dashboard öffnen (geht am Handy) und mit deinem Spotify-Konto anmelden.\n2. „Create app“: Name „Uzai“, Redirect URI http://127.0.0.1:8888/callback, „Web API“ anhaken, speichern.\n3. Unter „User Management“ dich mit der E-Mail deines Spotify-Kontos eintragen.\n4. Die Client-ID kopieren und hier einfügen. Spotify verlangt dafür Premium."


static func start(main: Main, done: Callable = Callable()) -> void:
	if str(Config.get_value("accounts.spotify_client_id", "")) != "":
		_browser(main, done)
		return
	main.open_dialog("Eigene Spotify-App", steps_text(), [
		["Client-ID eintragen", func() -> void: _ask_id(main, done)],
		["Später", func() -> void: pass],
	], "music")


static func _ask_id(main: Main, done: Callable) -> void:
	main.open_keyboard("Spotify-Client-ID", "", func(v: String) -> void:
		var cid := v.strip_edges()
		if not valid_id(cid):
			Toasts.show_toast("Das ist keine Client-ID", "Im Dashboard unter deiner App → Settings nochmal kopieren: 32 Zeichen aus Ziffern und a–f.", "warning", { "ms": 6000 })
			return
		Config.set_value("accounts.spotify_client_id", cid)
		_browser(main, done)
	, false, DASHBOARD)


## Spotifys Client-IDs: 32 Zeichen hexadezimal.
static func valid_id(cid: String) -> bool:
	if cid.length() != 32:
		return false
	for ch in cid.to_lower():
		if not ch in "0123456789abcdef":
			return false
	return true


static func _browser(main: Main, done: Callable) -> void:
	Config.set_value("system.music_mode", "spotify")
	main.open_dialog("Mit Spotify verbinden", "Spotify fragt einmal im Browser am PC, ob Uzai deine Playlists sehen und die Musik steuern darf. Danach bleibt Uzai verbunden.", [
		["Browser öffnen", func() -> void:
			Toasts.show_toast("Spotify-Anmeldung", "Im Browser bestätigen. Danach geht es hier weiter.", "music")
			var err: String = await Music.connect_spotify()
			Toasts.show_toast("Spotify verbunden" if err == "" else "Spotify nicht verbunden", err, "music" if err == "" else "warning")
			if done.is_valid():
				done.call(err)],
		["Später", func() -> void: pass],
	], "music")

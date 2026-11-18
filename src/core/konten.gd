extends RefCounted
## Konten und Datenschutz (Punkte 13, 77): welche Dienste Uzai kennt, was es je Dienst auf diesem
## PC speichert, wohin es spricht – und was „Abmelden“ vergisst. Reine Daten und Regeln (getestet in
## tests/logic_konten.gd); die Einstellungen zeigen sie unter Konten → Gespeichert und gesendet.
##
## Grundsatz (R6): Uzai hat keine eigenen Server. Jede Verbindung geht direkt von diesem PC zum
## jeweiligen Dienst, und nur, wenn du ihn nutzt; nichts wird mitgezählt (keine Telemetrie).
##
## keys: alles, was zur Anmeldung gehört – Abmelden leert genau diese Einträge. app: deine eigene
## Entwickler-App beim Dienst (Client-ID, Client-Secret); bleibt beim Abmelden, wenn du sie nicht
## ausdrücklich mit löschst, damit ein neues Anmelden ohne neue Einrichtung geht.
## page: Unterseite unter Einstellungen → Konten, auf der man sich verbindet ("" = keine).

const SERVICES := [
	{ "id": "steam", "name": "Steam", "icon": "steam", "page": "Steam",
		"keys": ["accounts.steam_chat_refresh", "accounts.steam_chat_access", "accounts.steam_chat_id", "accounts.steam_chat_name",
			"accounts.steam_key", "accounts.steam_id"], "files": ["cache/freunde_feed.json"],
		"stores": "Die Anmeldung aus der Steam-App (zum Erneuern und ein kurzer Zugang), deine Steam-ID und dein Steam-Name; freiwillig dein Web-API-Schlüssel.",
		"talks": "Direkt zu Steam (api.steampowered.com, steamcommunity.com, Steams Chat-Server): Freunde, Erfolge, Spielzeit, Wunschliste und Chat. Shop und Spielbilder lädt Uzai auch ohne Anmeldung von Steam." },
	{ "id": "epic", "name": "Epic Games", "icon": "games", "page": "Epic Games",
		"keys": ["accounts.epic_refresh", "accounts.epic_name", "accounts.epic_account_id"],
		"stores": "Die Anmeldung zum Erneuern, dein Epic-Name und deine Konto-ID, dazu die Liste deiner gekauften Spiele.",
		"talks": "Direkt zu Epics Servern: Anmeldung, Bibliothek, Katalog und Einmal-Code beim Spielstart." },
	{ "id": "discord", "name": "Discord", "icon": "discord", "page": "Discord",
		"keys": ["accounts.discord_token", "accounts.discord_refresh", "accounts.discord_expires",
			"accounts.discord_dm_token", "accounts.discord_dm_refresh", "accounts.discord_dm_expires",
			"accounts.discord_scope", "accounts.discord_last_guild"],
		"app": ["accounts.discord_client_id", "accounts.discord_client_secret"],
		"stores": "Die Freigabe aus der Discord-App (Zugang und Erneuerung), getrennt für Sprachkanal und Nachrichten. Freiwillig deine eigene Discord-App: App-ID und Client-Secret.",
		"talks": "Zur Discord-App auf diesem PC und zu discord.com, um die Freigabe zu erneuern; Nachrichten über Discords offizielles Social SDK. Der Status „Spielt …“ nennt Titel, Laden oder System und die öffentliche Adresse des Covers (Steam, Epic, SteamGridDB oder Libretro) – eigene Bilder nie." },
	{ "id": "spotify", "name": "Spotify", "icon": "music", "page": "Spotify",
		"keys": ["accounts.spotify_web", "accounts.spotify_app_refresh", "accounts.spotify_refresh"],
		"app": ["accounts.spotify_client_id"],
		"stores": "Mit Spotify angemeldet: die Anmeldung im eigenen, verschlüsselten Ordner des Browser-Kerns (nur Spotify). Mit eigener Spotify-App: die Anmeldung zum Erneuern und ihre Client-ID.",
		"talks": "Direkt zu Spotify (Anmeldung, Musik, Bibliothek) und über Spotify Connect zur Spotify-App auf diesem PC." },
	{ "id": "youtube", "name": "YouTube", "icon": "video", "page": "YouTube",
		"keys": ["youtube.refresh", "youtube.account", "accounts.youtube_tv_refresh", "accounts.youtube_tv_name"],
		"app": ["youtube.client_id", "youtube.client_secret"],
		"stores": "Mit Google: die Anmeldung zum Erneuern und dein Kontoname. TV-Anmeldung: die Anmeldung zum Erneuern und dein Name. Dein eigener Google-Zugang: Client-ID und Clientschlüssel.",
		"talks": "Direkt zu Google (Anmeldung, YouTube) und youtube.com. SponsorBlock bekommt nur die ersten vier Zeichen einer Prüfsumme der Video-ID, nie die Video-ID selbst." },
	{ "id": "twitch", "name": "Twitch", "icon": "live", "page": "Twitch",
		"keys": ["accounts.twitch_refresh", "accounts.twitch_access", "accounts.twitch_access_until", "accounts.twitch_token_client",
			"accounts.twitch_name", "accounts.twitch_login", "accounts.twitch_user_id"],
		"app": ["accounts.twitch_client_id"],
		"stores": "Die Anmeldung (Zugang und Erneuerung) und dein Twitch-Name; freiwillig eine eigene Client-ID.",
		"talks": "Direkt zu Twitch (id.twitch.tv, gql.twitch.tv, api.twitch.tv)." },
	{ "id": "nuvio", "name": "Nuvio", "icon": "qr", "page": "Nuvio",
		"keys": ["nuvio.refresh", "nuvio.access", "nuvio.expires", "nuvio.owner", "nuvio.email", "nuvio.user_id", "nuvio.addon_urls"],
		"stores": "Die Anmeldung (Zugang und Erneuerung), deine E-Mail-Adresse, deine Konto-ID und die Adressen deiner Addons.",
		"talks": "Direkt zu Nuvio (api.nuvio.tv): Addons, Plugins, Bibliothek und Weiterschauen werden mit deinem Konto abgeglichen." },
	{ "id": "plex", "name": "Plex", "icon": "drive", "page": "Filme-Quellen",
		"keys": ["plex.token", "plex.server_token", "plex.server", "plex.user"],
		"stores": "Zugangsschlüssel, Plex-Name und gewählter Server.",
		"talks": "Zu plex.tv (Anmeldung über plex.tv/link und die Liste deiner Server) und direkt zu deinem Plex-Server: Bibliotheken, Bilder, Wiedergabe und Fortschritt." },
	{ "id": "jellyfin", "name": "Jellyfin", "icon": "drive", "page": "Filme-Quellen",
		"keys": ["jellyfin.token", "jellyfin.server", "jellyfin.user"],
		"stores": "Serveradresse, Benutzername und Zugangsschlüssel.",
		"talks": "Nur zu deinem Jellyfin-Server, im Heimnetz auf deinen Wunsch auch unverschlüsselt. Die Suche im Heimnetz fragt nur auf Knopfdruck einmal kurz per Rundruf." },
	{ "id": "emby", "name": "Emby", "icon": "drive", "page": "Filme-Quellen",
		"keys": ["emby.token", "emby.server", "emby.user"],
		"stores": "Serveradresse, Benutzername und Zugangsschlüssel.",
		"talks": "Nur zu deinem Emby-Server, im Heimnetz auf deinen Wunsch auch unverschlüsselt. Die Suche im Heimnetz fragt nur auf Knopfdruck einmal kurz per Rundruf." },
	{ "id": "stremio", "name": "Stremio", "icon": "bookmark", "page": "Filme-Quellen",
		"keys": ["stremio.auth", "stremio.email"],
		"stores": "Zugangsschlüssel und E-Mail-Adresse.",
		"talks": "Zu link.stremio.com (Anmeldung per Code) und api.strem.io: deine Bibliothek, Weiterschauen und die Liste deiner Addons." },
	{ "id": "retroachievements", "name": "RetroAchievements", "icon": "retro", "page": "RetroAchievements",
		"keys": ["accounts.ra_user", "accounts.ra_key"], "files": ["cache/freunde_feed.json"],
		"stores": "Dein Benutzername und dein Web-API-Schlüssel.",
		"talks": "Direkt zu retroachievements.org; Name und Schlüssel gehen bei jeder Abfrage mit." },
	{ "id": "steamgriddb", "name": "SteamGridDB", "icon": "image", "page": "SteamGridDB",
		"keys": ["accounts.sgdb_key"],
		"stores": "Dein Schlüssel.",
		"talks": "Zu steamgriddb.com, wenn Uzai dort Bilder sucht: der Schlüssel und der Name oder die Steam-Nummer des Spiels." },
	{ "id": "iidb", "name": "iiDB", "icon": "image", "page": "iiDB",
		"keys": ["accounts.iidb_key"],
		"stores": "Dein Schlüssel. Je Spiel merkt Uzai die Nummer des Spiels bei iiDB – keine Angaben zu dir.",
		"talks": "Zu iidb-api.iisu.network, wenn Uzai dort Bilder oder den Klang eines Spiels sucht: der Schlüssel und Titel, Seriennummer oder Prüfsumme (MD5) des Spiels. Bilder und Klänge lädt Uzai ohne Schlüssel von iiSUs Dateiserver." },
	{ "id": "screenscraper", "name": "ScreenScraper", "icon": "image", "page": "",
		"keys": ["accounts.ss_user", "accounts.ss_pass", "accounts.ss_devid", "accounts.ss_devpass"],
		"stores": "Dein freiwilliges Konto und, bei eigenen Builds, der Programmzugang.",
		"talks": "Zu api.screenscraper.fr, wenn Uzai Bilder sucht: Zugangsdaten, System, Dateiname, -größe und Prüfsumme (MD5) des Spiels, notfalls sein Name." },
	{ "id": "tmdb", "name": "TMDB", "icon": "video", "page": "",
		"keys": ["movies.tmdb_key"],
		"stores": "Dein Schlüssel.",
		"talks": "Zu api.themoviedb.org: der Schlüssel und die IMDb- oder TMDB-Nummer eines Films oder einer Serie." },
]

# Gemeinsame Zustandstabellen (src/core/zustand.gd, Übersicht docs/ZUSTAENDE.md).

## Konto bei einem Dienst (Twitch, YouTube wie am Fernseher, Epic Games): aus, angemeldet (bereit), gerade gestört
## (fehler: Erneuern ging nicht, der nächste Abruf versucht es neu) oder abgelaufen (neu anmelden; der Name bleibt für
## den Hinweis). Abmelden führt von überall zu „aus“.
const ZUSTAENDE_KONTO := { "*": ["aus"], "aus": ["bereit", "abgelaufen"], "bereit": ["fehler", "abgelaufen"],
	"fehler": ["bereit", "abgelaufen"], "abgelaufen": ["bereit"] }
## Anmelde-Ebene mit Eingabe am Handy oder auf der Tastatur (Epic-Code, RetroAchievements, SteamGridDB): eingeben,
## prüfen, fertig oder Fehler mit „Nochmal“. Die Handy-Seite bleibt offen und darf auch danach noch einmal schicken.
const ZUSTAENDE_PRUEFEN := { "start": ["busy", "error"], "busy": ["done", "error"], "error": ["start", "busy"],
	"done": ["busy", "error"] }


static func find(id: String) -> Dictionary:
	for s in SERVICES:
		if s.id == id:
			return s
	return {}


## Nur ein Schlüssel, keine Anmeldung (SteamGridDB, TMDB): „eingetragen“ statt „angemeldet“.
static func key_only(id: String) -> bool:
	return str(find(id).get("page", "")) == ""


## Leerer Wert eines Eintrags: Ablaufzeiten sind Zahlen, alles andere Text.
static func empty_of(key: String) -> Variant:
	if key == "accounts.spotify_web":
		return false
	# Adressen der Addons aus dem Nuvio-Konto (verschlüsselt, oft mit Schlüssel im Pfad): beim Abmelden leer; zählen
	# allein nicht als Anmeldung.
	if key == "nuvio.addon_urls":
		return {}
	return 0 if key.ends_with("_expires") or key.ends_with(".expires") or key.ends_with("_until") else ""


## Hat Uzai für diesen Dienst etwas zur Anmeldung gespeichert? get: wie Config.get_value(key, default).
## Eine Ablaufzeit allein zählt nicht.
static func stored(id: String, get_value: Callable) -> bool:
	for k in find(id).get("keys", []):
		if (empty_of(k) is String or empty_of(k) is bool) and _filled(get_value.call(k, "")):
			return true
	return false


## Eigene Entwickler-App eingetragen?
static func has_app(id: String, get_value: Callable) -> bool:
	for k in find(id).get("app", []):
		if _filled(get_value.call(k, "")):
			return true
	return false


static func stored_count(get_value: Callable) -> int:
	return SERVICES.filter(func(s: Dictionary) -> bool: return stored(str(s.id), get_value)).size()


## Alles zur Anmeldung leeren (mit with_app auch die eigene App). set: wie Config.set_value(key, v).
## Dazu die Zwischenspeicher des Dienstes („files“, z. B. der Freunde-Feed mit Erfolgen von Freunden).
## Die Dienste selbst (Abmelden beim Anbieter, laufende Verbindungen) räumt die Oberfläche vorher ab.
static func forget(id: String, set_value: Callable, with_app := false) -> void:
	var s := find(id)
	for k in s.get("keys", []) + (s.get("app", []) if with_app else []):
		set_value.call(k, empty_of(k))
	for f in s.get("files", []):
		var p := Config.path(str(f))
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


static func _filled(v: Variant) -> bool:
	if v is bool:
		return v
	if v is String:
		return (v as String).strip_edges() != ""
	if v is int or v is float:
		return v != 0
	if v is Array or v is Dictionary:
		return not v.is_empty()
	return v != null

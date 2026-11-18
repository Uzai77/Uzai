extends Node
## Alle Einstellungen von Uzai. Was der Nutzer ändern kann, liegt hier und wird als
## settings.json im Datenordner gespeichert. Systeme, Emulatoren und Bildfilter kommen
## aus data/*.json und werden mit den Änderungen des Nutzers überlagert.

signal changed(path: String)

const VERSION := "0.16.92"
## GitHub-Repository (Selbst-Update, Fehlermeldung aufs Handy, User-Agent). Für das öffentliche Repository nur hier
## ändern (docs/UEBERGABE.md).
const REPO := "Uzai77/Uzai"
## Aufbau der Einstellungen (Punkt 56). Steigt bei jeder Änderung, die alte Werte umstellen muss;
## die Schritte stehen in _migrate. Vorher sichert Uzai den alten Stand (src/core/backup.gd).
const SETTINGS_VERSION := 4
const Backup := preload("res://src/core/backup.gd")
const CrashGuard := preload("res://src/core/crash_guard.gd")
const Zustand := preload("res://src/core/zustand.gd")
const Vault := preload("res://src/core/vault.gd")
const Lang := preload("res://src/core/lang.gd")
const Profiles := preload("res://src/core/profiles.gd")
const Fremd := preload("res://src/core/fremd.gd")
const Bildschirm := preload("res://src/core/bildschirm.gd")
## Sicherer Modus (Punkt 55): diese Werte gelten bis zum nächsten normalen Start, ohne dass sich
## die Einstellungen ändern – alles, was eigene Dateien lädt, Fremdes ausführt oder viel anstößt.
## Die Dienste (Freunde, Musik, Videos, Streams) startet main gar nicht erst.
const SAFE := {
	"theme.boot": "aus",
	"theme.font_file": "",
	"theme.background": "farbe",
	"theme.background_image": "",
	"theme.aurora": 0.0,
	"theme.motes": false,
	"library.scan_on_start": false,
	"movies.plugins_on": false,
	"capture.buffer": false,
	"lossless.auto": "aus",
	"system.on_start": "home",
}

const DEFAULTS := {
	"schema": 0,
	"uzai_version": "",
	"theme": {
		## Werte, die „theme“ sein können, nehmen den Grundwert des Aussehens (src/core/aussehen.gd,
		## in den Einstellungen „Standard“); eine eigene Wahl überschreibt ihn.
		"preset": "theme",
		"display": "theme",
		"rev": 14,
		"accent": "",
		"background": "theme",
		"background_image": "",
		"dim": 0.55,
		"aurora": 1.0,
		"corners": "theme",
		"focus": "rahmen",
		"cover_shape": "theme",
		"cover_size": "theme",
		"font": "theme",
		"font_file": "",
		"ui_scale": 1.0,
		"clock_24h": true,
		"boot": "theme",
		"motes": false,
		## Startseite: das Spielbild weichzeichnen (Standard aus: das Bild steht klar da, mit Verlauf).
		"bg_soft": false,
		"tint": true,
		"tabs": "auto",
		"sounds": true,
		"sound_volume": 0.6,
		"sound_space": true,
		"sound_set": "handpan",
		"music": 0.0,
		"music_track": "theme",
		"system_intro": "theme",
		"sections": ["games", "shop", "friends", "achievements", "apps", "settings"],
		"hidden_sections": [],
	},
	"library": {
		"rom_dirs": {},
		"media_dir": "",
		"steam_enabled": true,
		"steam_dir": "",
		"steam_owned": false,
		"steam_images": true,
		"libretro_images": true,
		"screenscraper": true,       # Bilder von ScreenScraper (nur, wenn das Paket den Programmzugang hat)
		"scrape_quellen": ["ss", "sgdb"],  # Spiele scrapen: Quellen in dieser Reihenfolge (media_daten.quellen_pruefen)
		"scrape_quellen_eigen": false,     # selbst gewählt: gilt dann auch bei PC-Spielen (Media.scrape_quellen_fuer)
		"spielklang": true,          # Klang von iiDB auf der Spielseite (nur mit iiDB-Schlüssel)
		"web_info": true,
		"epic_enabled": true,
		"epic_owned": true,
		"steam_install_lib": "",    ## Speicherort neuer Steam-Spiele ("" = Steams Standardordner)
		"install_auto": true,       ## Dialoge von Steam/Epic beim Installieren selbst bestätigen
		"epic_uzai": false,         ## Epic-Spiele mit Uzais eigenem Installer (ohne Launcher, inoffiziell)
		"epic_uzai_asked": false,   ## Hinweis dazu schon gezeigt
		"epic_uzai_dir": "",        ## Ordner, in den Uzai Epic-Spiele installiert
		"ea_enabled": true,
		## Weitere Launcher (src/library/stores.gd), je einzeln abschaltbar
		"gog_enabled": true,
		"gog_galaxy": true,         ## GOG-Spiele über GOG Galaxy starten (sonst die Programmdatei)
		"ubisoft_enabled": true,
		"battlenet_enabled": true,
		"xboxpc_enabled": true,
		"amazon_enabled": true,
		"itch_enabled": true,
		"riot_enabled": true,
		"show_hidden": false,
		"sub_order": [],            ## Quellen der Startseite, selbst angeordnet (langes A → Verschieben)
		"hidden_subs": [],          ## ausgeblendete Quellen (langes A → Ausblenden)
		"pc_dirs": [],
		"folder_hide": false,
		"sort": "recent",
		"filter": {},               ## Filter im Raster (src/library/game_filter.gd)
		"group": "",                ## Abschnitte im Raster: "", platform, genre, series, decade, year
		"presets": [],              ## gespeicherte Ansichten: [{ name, filter, group, sort }]
		"ansicht": {},              ## eigene Wahl je Quelle: { "ps2": "mosaik" }
		"regal_sort": "title",      ## Sortierung im Regal (src/library/regal.gd SORTEN)
		"scan_on_start": true,
	},
	"systems": {},
	"emulators": {},
	"filters": {},
	"shaderglass": { "exe": "", "enabled": true },
	"badges": { "real_logos": true, "rev": 2 },
	"apps": {
		"order": [],                ## Reihe der Apps, selbst angeordnet (langes A → Verschieben)
		"hidden": [],               ## ausgeblendete Apps (langes A → Ausblenden)
		"last": "",                 ## zuletzt benutzte App: der Reiter „Apps“ öffnet sie
		"extern": [],               ## eigene Apps: Store-Apps und Programme (src/core/apps_extern.gd)
		"leitfaden": {},            ## je eigener App: so oft stand beim Start die Belegung des Controllers (app_steuerung.gd)
	},
	## Uzai-Browser (src/core/browser_daten.gd): Lesezeichen, Apps, zuletzt besucht, Zoom und Stelle je Seite.
	"browser": {
		"suche": "google",
		"favoriten": [],
		"apps": [],
		"zuletzt": [],
		"verlauf": true,
		"zoom": {},
		"stellen": {},
		"sitzung": [],
		"kern_vorab": false,
		"kern_grafik": "hardware",  ## "software": Chromium ohne GPU (Rückfall, browser_wirt.gd), im Menü Browser-Kern
	},
	"youtube": {
		"mpv": "",
		"ytdlp": "",
		"quality": "1080",
		"display": "mpv",
		"cookies": "",
		"cookies_file": "",
		"subtitles": false,
		"sub_langs": "de,en",
		"autoplay": true,
		"hide_shorts": true,
		"shorts_tab": true,        # Reiter „Shorts“ unter Videos (Shorts der Abos, hochkant)
		"sponsorblock": ["sponsor"],
		"region": "DE",
		"volume": 100,
		"client_id": "",
		"client_secret": "",
		"refresh": "",
		"account": "",
		"updated": 0,
		"tv_history": false,      # Fernseher-Anmeldung: Gesehenes an YouTube melden (Standard aus)
	},
	"twitch": {
		"lang": "DE",           # Sprache der Reihe „Beliebt auf …“
	},
	"movies": {
		"enabled": true,
		"no_p2p": true,
		"addons": [],
		"addons_init": false,
		"refreshed": 0,
		"plugin_repos": [],
		"plugins_on": true,
		"tmdb_key": "",
		"quality": "auto",
		"lang_first": "auto",     # Quellen dieser Sprache zuerst: auto (Oberfläche), aus, de, en …
		"autoplay_next": true,
	},
	"launcher": {
		"admin_ok": [],      # Programme, die trotz Adminrechten ohne Rückfrage starten
	},
	"lossless": {
		"exe": "",
		"hotkey": "CTRL+ALT+S",
		"auto": "aus",
		"delay": 8.0,
		"filter": "aus",
	},
	"accounts": {
		"steam_key": "",
		"steam_id": "",
		"ra_user": "",
		"ra_key": "",
		"ra_toasts": true,
		"spotify_client_id": "",
		"spotify_refresh": "",
		"spotify_mode": "",          # "app" (Mit Spotify anmelden) | "eigen" (eigene Client-ID) | "" (Spotify-Anmeldung vor eigener)
		"spotify_web": false,        # mit Spotify angemeldet (die Anmeldung liegt im Ordner der Spotify-Sitzung, spotify_web.gd)
		"spotify_app_refresh": "",   # frühere QR-Anmeldung (entfällt; wird beim Start geleert)
		"spotify_app_blocked": 0,    # wann Spotify Bibliothek und Mixe auf diesem Weg nicht zuließ (Unix-Zeit, 0 = nie): Grundmodus
		"discord_servers": [],
		"discord_presence": true,
		"discord_client_id": "",
		"discord_client_secret": "",
		"discord_voice": true,
		"discord_dm": true,
		"discord_token": "",
		"discord_refresh": "",
		"discord_expires": 0,
		"discord_uzai_app": false,   # Uzais eingebaute Discord-App ging für dieses Konto schon einmal (Voice.uzai_app_direkt)
		"sgdb_key": "",
		"iidb_key": "",              # iiDB (iiSU): eigener Schlüssel, im Tresor, gilt für den ganzen PC
		"ss_user": "",               # ScreenScraper-Konto (freiwillig, hebt das Tageskontingent)
		"ss_pass": "",
		"ss_devid": "",              # Programmzugang für eigene Builds (sonst data/screenscraper_dev.json)
		"ss_devpass": "",
		"epic_refresh": "",       # Epic-Konto (inoffiziell wie Heroic/Legendary): nur die Erneuerungs-Anmeldung
		"epic_name": "",
		"epic_account_id": "",
		"epic_game_login": true,  # Epic-Spiele von Uzai: beim Start ein frischer Einmal-Code für die Anmeldung im Spiel (wie Legendary)
		"youtube_tv_refresh": "", # YouTube wie auf dem Fernseher (inoffiziell, SmartTube-Weg): nur die Erneuerungs-Anmeldung
		"youtube_tv_name": "",
		# Twitch (Bereich Streams): Anmeldung wie die Twitch-App am Fernseher (inoffiziell) oder mit eigener Client-ID
		"twitch_refresh": "",       # Erneuerungs-Anmeldung
		"twitch_access": "",        # Zugang (auch mit Erneuerung gespeichert: Erneuern klappt nicht immer)
		"twitch_access_until": 0,   # Ablauf des Zugangs (Unix-Zeit, 0 = unbekannt)
		"twitch_token_client": "",  # Kennung, zu der die Anmeldung gehört
		"twitch_name": "",
		"twitch_login": "",
		"twitch_user_id": "",
		"twitch_client_id": "",     # eigene Client-ID (dev.twitch.tv, Typ „Öffentlich“), freiwillig
		"twitch_mode": "",          # "eigen" (eigene Client-ID) | "" (wie die Twitch-App am Fernseher)
	},
	"controller": {
		"glyphs": "auto",
		"swap_ab": false,
		"guide_combo": true,
		"guide_hold": "menu",     # Guide-Taste halten: "menu" (Schnellmenü), "rest" (Ruhemodus), "aus"
		"steam_guide_aus": false, # Uzai hat Steams Guide-Taste abgeschaltet und zieht neue Konten nach
		"steam_guide_standard": false, # das Abschalten ist einmal von selbst geschehen (steam_guide.gd beim_start)
		"deadzone": 0.5,
		"repeat_delay": 0.4,
		"repeat_rate": 0.12,
		"vibration": true,
		"hide_mouse": true,
	},
	"notify": {
		"steam": true,
		"discord": true,
		"in_game": true,
		# Erfolgs-Pop-ups (src/core/unlocks.gd): an/aus, Position unten/oben, eigener Klang, Seltene hervorheben
		"unlock_popups": true,
		"unlock_pos": "unten",
		"unlock_sound": true,
		"unlock_rare": true,
		# Steams eigene Mitteilungs-Fenster unsichtbar, solange Uzai läuft (src/core/steam_still.gd)
		"steam_still": true,
		"wish_sales": true,       # Spiel der Steam-Wunschliste neu im Angebot (src/core/store.gd)
		"requests_seen": [],      # schon gemeldete Freundschaftsanfragen (src/core/friend_requests.gd)
		"ruhe_film": true,        # Nicht stören von selbst, solange ein Film läuft (src/core/nicht_stoeren.gd)
		"watch": [],              # Melden, wenn online: Steam-IDs (src/core/notify.gd)
	},
	# Download-Zentrale (src/core/dl_queue.gd, src/core/installs.gd)
	"downloads": {
		"night": false,           # Warteschlange nachts laden – nur im Ruhemodus, nie den PC wecken
		"night_from": "1",        # Zeitfenster: ab … Uhr
		"night_to": "6",          # … bis … Uhr
		"night_updates": true,    # dazu anstehende Steam-Updates (braucht die Steam-Anmeldung)
		"queue": [],              # Uzais Warteschlange [{ id, kind, when, added, accept }]
	},
	# Ruhemodus und Spielstände (src/core/rest.gd, src/core/quick_resume.gd)
	"rest": {
		"screen_off": false,      # Bildschirm aus (nur für den Augenblick); aus: der Ruhebildschirm läuft
		"mute": true,             # Ton des Spiels aus
		"pc_suspend": "safe",     # PC-Spiele anhalten: "off" oder "safe" (nur ohne Anti-Cheat, offline)
		"quick_resume": true,     # Emulatoren: beim Beenden über Uzai die Stelle merken
		# Ruhebildschirm (src/core/saver.gd)
		"saver": "10",            # nach so vielen Minuten ohne Bedienung im Menü, "0" = aus
		"saver_motion": "fahrt",  # "fahrt" (Kamerafahrt) oder "ruhig" (nur überblenden)
		"saver_shots": false,     # auch eigene Bildschirmfotos zeigen
		"saver_rest": "0",        # danach in den Ruhemodus: nach so vielen Minuten, "0" = nie
		"pads_off": false,        # kabellose Xbox-Controller beim Einschlafen ausschalten (Akku über Nacht)
	},
	"system": {
		"language": "de",               # Sprache der Oberfläche (src/core/lang.gd, i18n/*.json)
		"country": "auto",              # Land für Preise und Angebote: "auto" (nach Sprache und Windows) oder z. B. "AT"
		"backup_before_update": true,   # vor jedem Update den Stand sichern (backups/)
		"updates": "auto",              # Selbst-Update: "auto" (laden, beim Schließen einspielen), "melden", "aus"
		"autostart": false,
		"grafik": "realistisch",   # "realistisch" (Forward+, Zimmer mit GI) oder "kompatibel" (einfacher Renderer)
		"background_wake": true,   # nach dem Schließen wartet ein kleiner Wächter auf die Guide-Taste
		"power_off": true,         # Ausschalt-Animation mit Klang beim Schließen und Ausschalten
		"on_start": "home",
		"pause_on_guide": true,
		"guide_tiles": [],              # eigene Kacheln im Guide (Reiter Spiel), je Platz eine Kennung, "" = automatisch
		"guide_smart": true,            # Guide passend zur Lage (Spielstand, Übertragen … nach vorn)
		"quick_tiles": [],              # Kacheln im Schnellmenü in eigener Reihenfolge, [] = Standard (guide_quick_wahl.gd)
		"perf_corner": false,           # Leistung klein in der Ecke über dem Spiel (src/ui/perf_corner.gd)
		"power_restore": "",            # Energieprofil von vor dem Umschalten im Guide: nach dem Spiel zurück (src/core/perf_live.gd)
		"notifications": true,
		"music_mode": "lokal",        # ohne Spotify ein eigener Player für den Musikordner
		"last_game": "",
		"first_run": true,
		"seen_version": "",        # bis zu dieser Fassung ist „Was ist neu“ gezeigt (src/core/whats_new.gd)
		"game_page": true,
		"round_summary": true,     # nach dem Spielen: „Gerade gespielt“ unter „Für dich“ mit Zusammenfassung
		"live_tiles": true,        # lebendige Kacheln: Zustand des Spiels auf dem Cover (src/core/kacheln.gd)
		"player_name": "Spieler 1",
		"quick_messages": ["Bin gleich da!", "Lust zu zocken?", "GG!", "Einen Moment, bin im Menü."],
		"clip_keys": "WIN+ALT+G",
		"stream_keys": "CTRL+SHIFT+F9",
		"live_method": "auto",
		"steam_overlay_keys": "SHIFT+TAB",
		"search_online": true,     # globale Suche fragt nach kurzer Tipp-Pause auch Shop, Musik, Streams, Filme
		"spotify_ort": "pc",       # Spotify spielt auf: "pc" (immer dieser PC) oder "aktiv" (das Gerät, das gerade läuft)
		"nacht_laut": "aus",       # Nachts leiser (src/core/nacht_ton.gd): Windows-Lautstärke höchstens so viel Prozent
		"nacht_von": "22",         # … ab dieser Stunde
		"nacht_bis": "7",          # … bis zu dieser Stunde
	},
	# Tonausgabe (src/core/tonwahl.gd): das feste Gerät und FxSound. Gilt für den ganzen PC.
	"ton": {
		"fest_id": "",              # Kennung des festen Ausgabegeräts (wie audio-list), "" = keins
		"fest_name": "",            # sein Name bei Windows (so kennt es auch FxSound)
		"fxsound_da": false,        # FxSound ist auf diesem PC installiert (beim Start nachgesehen)
		"fxsound_start": false,     # FxSound mit Uzai still starten
	},
	# Bildschirm (src/core/display_fit.gd): einmal beim ersten Start erkannt, danach auf Wunsch.
	"display": {
		"fitted": false,            # schon einmal erkannt (beim ersten Start)
		"menu_fps": "auto",         # auto: über 144 Hz die halbe Bildrate im Menü; voll: immer alle
		"light": "auto",            # Leichter Modus (src/core/leicht.gd): aus, auto (einmal vorschlagen), an
		"light_asked": false,       # schon einmal vorgeschlagen
		"seen": {},                 # zuletzt erkannt: Name, Anschluss, Größe, Hz, HDR
		"screen": "auto",           # Bildschirm für Uzai (src/core/bildschirm.gd): auto oder "1", "2", …
		"skalen": {},               # Größe der Oberfläche je Bildschirm („3840x2160@288“: 1.0)
		"dpi_eigen": true,          # bei mehreren Bildschirmen scharf rechnen (ein Neustart beim Start)
		"dpi_gleich": "",           # Anordnung, bei der alle Bildschirme gleich skaliert waren (kein Neustart nötig)
	},
	# Dein Zimmer (Punkt 131, src/room/): andere Art der Startseite; das Zimmer selbst liegt in zimmer/.
	"room": {
		"start": "klassisch",       # beim Einschalten: klassisch (2D) oder zimmer (3D)
		"kachel": true,             # Kachel „Dein Zimmer“ am Ende von „Zuletzt“ auf der Startseite
		"grafik": "auto",           # Grafik im Zimmer (src/room/licht.gd STUFEN): auto, hoch, mittel, leicht
		"fps": "bildschirm",        # Bildrate im Zimmer (src/room/leistung.gd RATEN): bildschirm, 60, 30
		# Zimmer online (src/room/online.gd, docs/ZIMMER_SICHERHEIT.md): Standard aus. Online geht es nur mit
		# allen vier Bedingungen (Online.darf_online): eingeschaltet, ohne Adminrechte, Abschottung bestanden,
		# Hinweis zur IP-Adresse gesehen.
		"online": false,
		"online_hinweis": false,    # der Hinweis „Eingeladene sehen deine IP-Adresse“ wurde bestätigt
		"online_abschottung": {},   # { fassung, ok }: „Abschottung prüfen“ zuletzt bestanden mit dieser Uzai-Fassung
		"online_test": false,       # Testbetrieb: echte Relays + WebRTC nur für den Verbindungstest (ohne Admin, nach der Probe)
		"online_max": 4,            # höchstens so viele Gäste (1–8)
		"online_gueltig": 60,       # Minuten, die ein Einladungslink gilt (15, 60, 1440)
		"online_einmalig": true,    # unbenutzt: Einladungen sind immer nur einmal nutzbar
		"online_moebel": false,     # Gäste dürfen Möbel umstellen (Schalter erst, wenn das Protokoll es kann)
	},
	# Uzais eigene Aufnahme (Clips, Aufnahmen); Werte wie capture_logic.gd DEFAULTS.
	"capture": {
		"via": "uzai",
		"buffer": true,
		"length": "30",
		"quality": "1080",
		"fps": "60",
		"source": "screen",
		"audio": true,
		"mic": false,
		"folder": "",
		"cap_gb": "25",
		"battery": false,
		"videos": false,
		"discord_mb": "10",
		"hotkey": true,
		"working": "",
	},
}

var data_dir := "user://"
var portable := false
var settings: Dictionary = {}
var _base_systems: Array = []
var _base_emulators: Array = []
var _base_filters: Array = []
## Zusammengeführte Systeme, Emulatoren und Filter. Früher wurde bei jedem Aufruf alles tief kopiert –
## Library.is_visible fragt pro Spiel, bei 1000 Spielen kostete ein Bereichswechsel Sekunden.
## Ergebnisse gelten als nur lesbar; geändert wird über set_system/set_emulator/set_value.
var _merged := {}
var _merged_by := {}
var _save_timer: Timer
## Hinweise für den ersten Bildschirm (repariert, zurückgeholt, gesichert) – main zeigt sie.
var notices: Array = []
## Absturzschutz (src/core/crash_guard.gd): wie das letzte Uzai zu ging ({} = sauber) und ob
## dieses im Sicheren Modus läuft.
var last_crash: Dictionary = {}
var safe_mode := false
var _run: Dictionary = {}
var _auto := 0                     ## so oft hintereinander nach einem Absturz neu gestartet (Wächter)
## Tresor (src/core/vault.gd): Schlüssel kommen im eigenen Faden; bis dahin bleibt Versiegeltes zu.
var vault_how := ""                ## "dpapi", "test" oder "" (kein Schutz möglich)
var _vault_keys: Array = []
const SHARED_VAULT_DIR := "tresor"
var _vault_job: Thread
## Gemeinsamer Tresor (für alle Profile, Ordner „tresor“ im Datenordner): nur für Geheimes, das
## Profiles.SHARED nennt (der SteamGridDB-Schlüssel gilt für den ganzen PC).
var _shared_keys_list: Array = []
var _shared_job: Thread
var _save_waiting := false
## Werte nur für eine Weile (Spiel-Profil: Controller in Uzais Menü, Pop-ups im Spiel). Nie
## gespeichert – ein Absturz vergisst sie von selbst. Siehe set_temp.
var _temp := {}
## Nutzerprofile (Roadmap 109, src/core/profiles.gd): je Uzai-Lauf genau eines. Ein Wechsel
## startet Uzai mit --profil=<id> neu – so bleibt keine Anmeldung des vorigen Profils im Speicher.
var profile_id := ""
var profile_dir := ""
var profiles: Dictionary = {}      ## geprüfte profiles.json
var profile_chosen := false        ## beim Start schon gewählt (--profil=…): keine Auswahl zeigen
var profile_welcome := false       ## nach einem Wechsel gestartet (--profilwechsel): Begrüßung statt Startanimation
signal profiles_changed


## Wann jeder Grunddienst (Autoload) in den Baum kam, ms seit Programmstart: [[Name, ms], …] – der Abstand zum
## nächsten ist ungefähr, was sein Start gekostet hat (Startphasen im Leistungsprotokoll, Perf.booted).
var autoload_ms: Array = []
var erzeugt_ms := Time.get_ticks_msec()     ## wann Config entstand (vor dem Laden der übrigen Grunddienste?)


func _enter_tree() -> void:
	autoload_ms.append(["Config", Time.get_ticks_msec()])
	get_tree().node_added.connect(_autoload_kam)


func _autoload_kam(n: Node) -> void:
	if n.get_parent() == get_tree().root:
		autoload_ms.append([str(n.name), Time.get_ticks_msec()])
		var name_ := str(n.name)
		n.ready.connect(func() -> void: autoload_fertig_ms.append([name_, Time.get_ticks_msec()]), CONNECT_ONE_SHOT)


## Wann jeder Grunddienst mit _ready fertig war (ms seit Programmstart), in der Reihenfolge, in der Godot sie aufruft –
## der Abstand zum vorigen ist, was sein _ready gekostet hat.
var autoload_fertig_ms: Array = []


## main ist da: ab hier zählt nichts mehr als Grunddienst.
func autoloads_fertig() -> void:
	if get_tree().node_added.is_connected(_autoload_kam):
		get_tree().node_added.disconnect(_autoload_kam)
	autoload_ms.append(["main", Time.get_ticks_msec()])


func _ready() -> void:
	# Vor dem ersten Kindprozess (Tresor, Helfer): die Startvariablen für das scharfe Bild wieder
	# aus der Umgebung nehmen (bildschirm.gd).
	Bildschirm.start()
	_wait_for_previous()
	_resolve_data_dir()
	# Vorgemerktes Wiederherstellen vor allem anderen (nichts ist geladen, auch kein Profil).
	var restored := Backup.apply_pending_restore(data_dir)
	if restored != "":
		notices.append(restored)
	# Welches Profil dieser Lauf hat (beim ersten Start mit Profilen: der bisherige Stand wird
	# gesichert und zum ersten Profil).
	_setup_profiles()
	# Dann: die PowerShell für den Tresor-Schlüssel (je Profil ein eigener) läuft, während der Rest lädt.
	_vault_job = Thread.new()
	_vault_job.start(Vault.load_keys.bind(profile_dir if profile_dir != "" else data_dir))
	if profile_dir != "":
		DirAccess.make_dir_recursive_absolute(data_dir.path_join(SHARED_VAULT_DIR))
		_shared_job = Thread.new()
		_shared_job.start(Vault.load_keys.bind(data_dir.path_join(SHARED_VAULT_DIR)))
	set_process(false)
	_check_last_run()
	_load_base_data()
	load_settings()
	Lang.apply(str(get_value("system.language", "de")))
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.6
	_save_timer.timeout.connect(save_settings)
	add_child(_save_timer)
	# Anmeldungen aus älteren Versionen stehen noch offen in der Datei: gleich versiegeln.
	if Vault.SECRETS.any(func(p: String) -> bool:
		var v: Variant = _raw(settings, p)
		return v != null and not Vault.is_sealed(v) and not (v is String and v == "") and not (v is Array and v.is_empty())):
		save_soon()
	_migrate_remote_play()
	autoload_fertig_ms.append(["Config", Time.get_ticks_msec()])


## Neustart (main.restart_uzai): warten, bis das alte Uzai ganz zu ist – sonst schriebe es noch,
## während hier eine Sicherung zurückkommt, und hielte den Steuer-Anschluss (Remote).
func _wait_for_previous() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--nach-neustart="):
			var old := int(a.substr(16))
			var until := Time.get_ticks_msec() + 15000
			while old > 0 and old != OS.get_process_id() and OS.is_process_running(old) and Time.get_ticks_msec() < until:
				OS.delay_msec(100)


func _check_last_run() -> void:
	var args := OS.get_cmdline_user_args()
	if not "--demo" in args:
		var m := CrashGuard.read(data_dir)
		var pid := int(m.get("pid", 0))
		last_crash = CrashGuard.verdict(m, OS.get_process_id(), pid > 0 and OS.is_process_running(pid))
		_auto = int(m.get("auto", 0)) + 1 if "--nach-absturz" in args else 0
	safe_mode = "--sicherer-modus" in args or CrashGuard.needs_safe(last_crash)


## main, sobald feststeht, dass dieses Uzai das laufende ist (kein zweites, das nur weitergibt).
## Nach CrashGuard.QUICK_S gilt der Start als gelungen.
func run_started() -> void:
	if "--demo" in OS.get_cmdline_user_args():
		return
	var now := int(Time.get_unix_time_from_system())
	_run = { "pid": OS.get_process_id(), "started": now, "seen": now, "version": VERSION,
		"streak": int(last_crash.get("streak", 0)), "stable": false, "safe": safe_mode, "where": "", "auto": _auto }
	CrashGuard.write(data_dir, _run)
	get_tree().create_timer(CrashGuard.QUICK_S).timeout.connect(func() -> void:
		_run.stable = true
		_run.streak = 0
		_touch_run()
	)
	# Läuft es eine Weile, darf der Wächter wieder neu starten.
	get_tree().create_timer(CrashGuard.CALM_S).timeout.connect(func() -> void:
		if int(_run.get("auto", 0)) > 0:
			_run.auto = 0
			_touch_run()
	)


## Wo Uzai gerade ist (Bereich, „spiel“; „aus“: Windows fährt herunter, kein Absturz).
func run_where(where: String) -> void:
	if _run.is_empty() or str(_run.where) == where:
		return
	_run.where = where
	_touch_run()


func _touch_run() -> void:
	_run.seen = int(Time.get_unix_time_from_system())
	# Stand der Zustandsautomaten mitschreiben: Endet Uzai unerwartet, nennt der Fehlerbericht ihn.
	_run.zustaende = Array(Zustand.lage_text(10))
	CrashGuard.write(data_dir, _run)


## Sauber beendet (jeder Weg über get_tree().quit()): die Markierung kommt weg.
func _exit_tree() -> void:
	if not _run.is_empty():
		CrashGuard.clear(data_dir, OS.get_process_id())
	Lang.release()
	# Ein Speichern, das noch auf den Tresor-Schlüssel wartete, jetzt nachholen. Beide Fäden abwarten:
	# Ein noch laufender Thread, den Godot beim Beenden zerstört, brachte gelegentlich Signal 11.
	_keys()
	_shared_keys()
	if _save_waiting:
		_save_waiting = false
		save_settings()
	# Eine Änderung der letzten 0,6 s (save_soon) wartete noch auf ihren Zeitgeber: jetzt schreiben.
	elif _save_timer and not _save_timer.is_stopped():
		_save_timer.stop()
		save_settings()


## Einmal umstellen: Emulator-Spiele starten wieder normal (Steam zeigt dann ihren Namen), über
## den Remote-Play-Spender nur noch auf Wunsch („Mit Freund spielen“ auf der Spielseite).
func _migrate_remote_play() -> void:
	if bool(get_value("remoteplay.default_v2", false)):
		return
	set_value("remoteplay.emulators", false)
	set_value("remoteplay.default_v2", true)


func _resolve_data_dir() -> void:
	# Portabler Modus: liegt neben der Uzai.exe ein Ordner "uzai-daten", wird alles dort gespeichert.
	var exe_dir := OS.get_executable_path().get_base_dir()
	var p := exe_dir.path_join("uzai-daten")
	# Für Tests: eigener Datenordner pro Lauf (mehrere Rundgänge gleichzeitig stören sich nicht).
	var env := OS.get_environment("UZAI_DATA")
	if env != "":
		data_dir = env
	elif not OS.has_feature("editor") and DirAccess.dir_exists_absolute(p):
		data_dir = p
		portable = true
	else:
		data_dir = ProjectSettings.globalize_path("user://")
	for sub in ["cache", "cache/img", "media", "logs"]:
		DirAccess.make_dir_recursive_absolute(data_dir.path_join(sub))


## Zwischenspeicher begrenzen: die ältesten Einträge gehen (Uzai läuft oft tagelang).
static func cap(d: Dictionary, n: int) -> void:
	while d.size() > n:
		d.erase(d.keys()[0])


## Pfad im Datenordner. Was einem Profil gehört (Profiles.OWN_FILES/OWN_DIRS: Einstellungen,
## Verlauf, Zimmer …), liegt im Ordner des aktiven Profils – alle Module bekommen so von selbst
## ihre eigenen Daten.
func path(rel: String) -> String:
	if profile_dir != "" and Profiles.is_own_path(rel):
		return profile_dir.path_join(rel)
	return data_dir.path_join(rel)


## Pfad im gemeinsamen Datenordner, auch für Dateien, die sonst einem Profil gehören.
func shared_path(rel: String) -> String:
	return data_dir.path_join(rel)


# --- JSON-Hilfen -------------------------------------------------------------

## Liest eine JSON-Datei. Fehlt sie oder ist sie kaputt (Absturz oder Stromausfall beim
## Speichern), kommt die letzte gute Fassung (.bak) bzw. die halb geschriebene neue (.tmp) –
## früher ergab eine abgeschnittene library.json eine leere Bibliothek, die beim nächsten
## Speichern endgültig überschrieben wurde.
static func read_json(file_path: String, fallback: Variant = null) -> Variant:
	var v: Variant = _read_json_file(file_path)
	if v != null:
		return v
	for alt in [file_path + ".bak", file_path + ".tmp"]:
		v = _read_json_file(alt)
		if v != null:
			push_warning("Uzai: %s war nicht lesbar, nehme %s" % [file_path.get_file(), alt.get_file()])
			return v
	return fallback


static func _read_json_file(file_path: String) -> Variant:
	if not FileAccess.file_exists(file_path):
		return null
	var text := FileAccess.get_file_as_string(file_path)
	if text.is_empty():
		return null
	return Fremd.json_roh(text)


## Ohne Einzug: große Dateien (Bibliothek, Filme, Shop-Angaben) schreiben so ein Mehrfaches schneller.
## Nur die Einstellungen bleiben lesbar eingerückt – die öffnet man auch mal von Hand.
static func write_json(file_path: String, value: Variant, indent := "") -> bool:
	return write_text(file_path, JSON.stringify(value, indent))


## Einen fertigen Text sicher an die Stelle einer Datei bringen (erst schreiben und nachzählen, dann tauschen; die
## bisherige Fassung bleibt als .bak). write_json nutzt das; wer seinen Text selbst baut, auch.
static func write_text(file_path: String, text: String) -> bool:
	var tmp := file_path + ".tmp"
	if not DirAccess.dir_exists_absolute(file_path.get_base_dir()):
		DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Uzai: kann %s nicht schreiben" % file_path)
		return false
	var bytes := text.to_utf8_buffer()
	f.store_buffer(bytes)
	f.close()
	# Erst nachzählen, dann tauschen. Ist die Platte voll, bricht das Schreiben mittendrin ab: Die halbe Datei
	# ersetzte sonst die gute, und beim zweiten Versuch auch deren Kopie (.bak) – Einstellungen, Bibliothek oder
	# Spielzeiten wären weg. So bleibt die gute Fassung, und der Aufrufer erfährt, dass es nicht ging.
	if not ganz_geschrieben(tmp, bytes.size()):
		DirAccess.remove_absolute(tmp)
		push_warning("Uzai: %s ließ sich nicht ganz schreiben (Platte voll?) – die bisherige Fassung bleibt" % file_path)
		return false
	# Unter Windows ist Umbenennen „löschen, dann verschieben“: die bisherige Fassung als .bak
	# behalten, damit ein Absturz genau dazwischen nichts verliert (read_json nimmt sie dann).
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path + ".bak")
		DirAccess.rename_absolute(file_path, file_path + ".bak")
	var err := DirAccess.rename_absolute(tmp, file_path)
	if err != OK:
		# Ziel gerade gesperrt (Virenscanner, Sicherung): kurz warten, nochmal.
		OS.delay_msec(60)
		err = DirAccess.rename_absolute(tmp, file_path)
	if err != OK:
		push_warning("Uzai: kann %s nicht ersetzen (%d)" % [file_path, err])
		return false
	return true


## Liegt die Datei mit genau so vielen Bytes auf der Platte? (Nach dem Schließen: Erst dann zeigt sich ein Schreiben,
## das am vollen Datenträger scheiterte.)
static func ganz_geschrieben(file_path: String, bytes: int) -> bool:
	var f := FileAccess.open(file_path, FileAccess.READ)
	return f != null and f.get_length() == bytes


static func deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over.keys():
		if out.has(k) and out[k] is Dictionary and over[k] is Dictionary:
			out[k] = deep_merge(out[k], over[k])
		else:
			out[k] = over[k]
	return out


# --- Einstellungen -----------------------------------------------------------

func load_settings() -> void:
	# Eigene Einstellungen (im Ordner des Profils) und gemeinsame (gemeinsam.json) – zusammengeführt
	# wie früher eine settings.json; die gemeinsamen Werte gelten (Profiles.SHARED).
	var own_dir := profile_dir if profile_dir != "" else data_dir
	var repaired := false
	var saved: Variant = read_json(path("settings.json"), null)
	# Selbstreparatur: Datei da, aber samt .bak/.tmp unlesbar → die neueste tägliche Kopie.
	if not (saved is Dictionary) and FileAccess.file_exists(path("settings.json")):
		var snap := Backup.latest_settings(own_dir)
		if not snap.is_empty():
			saved = snap.data
			repaired = true
			notices.append("Deine Einstellungen waren beschädigt und sind repariert (Stand %s)." % str(snap.file).trim_prefix("settings-").trim_suffix(".json"))
	if not (saved is Dictionary):
		saved = {}
	var shared: Variant = read_json(shared_path(Profiles.SHARED_FILE), null)
	if not (shared is Dictionary) and FileAccess.file_exists(shared_path(Profiles.SHARED_FILE)):
		var snap2 := Backup.latest_settings(data_dir, "gemeinsam")
		if not snap2.is_empty():
			shared = snap2.data
			repaired = true
			notices.append(
					"Die gemeinsamen Einstellungen waren beschädigt und sind repariert (Stand %s)." % str(snap2.file).trim_prefix("gemeinsam-").trim_suffix(".json"))
	# SteamGridDB-Schlüssel gilt jetzt für den ganzen PC: Hat das Profil einen und der gemeinsame
	# Stand (noch) keinen, wird der des Profils einmalig übernommen (beim nächsten Speichern).
	var own_shared := {}
	for p in Profiles.SHARED:
		if shared_secret(p):
			var ov: Variant = _raw(saved, p)
			if ov is String and ov != "":
				own_shared[p] = ov
	if shared is Dictionary:
		saved = Profiles.merge_settings(saved, shared)
	for p in own_shared:
		var sv: Variant = _raw(saved, p)
		if not (sv is String) or sv == "":
			_put_path(saved, p, own_shared[p])
	var old_schema := int(saved.get("schema", 0))
	var old_version := str(saved.get("uzai_version", ""))
	# Update erkannt (ein vorhandener Stand einer anderen Version): erst sichern, dann umstellen.
	if not saved.is_empty() and old_version != VERSION \
			and bool((saved.get("system", {}) as Dictionary).get("backup_before_update", true) if saved.get("system") is Dictionary else true):
		var b := Backup.create(data_dir, "update-%s-%s" % [old_version if old_version != "" else "alt", VERSION])
		if not bool(b.ok):
			push_warning("Uzai: Sicherung vor dem Update ging nicht: " + str(b.error))
	settings = deep_merge(DEFAULTS, saved)
	sanitize(settings, DEFAULTS)
	_forget_merged()
	# 0.3.1: das neue, warme Farbschema löst das alte Standard-Schema ab (eigene Wahl bleibt).
	# (Hier zählt, was in der Datei stand: Ohne Angabe ist es ein alter Stand, auch wenn der Standard schon neuer ist.)
	if Fremd.zahl(Fremd.weg(saved, "theme/rev"), 1) < 3:
		# 0.4: neues Aussehen. Wer das alte Standard-Schema hatte, bekommt das neue.
		if str(settings.theme.get("preset", "")) in ["mitternacht", "glut"]:
			settings.theme["preset"] = "uzai"
		if str(settings.theme.get("display", "")) == "bricolage":
			settings.theme["display"] = "saira"
		settings.theme["motes"] = false
		settings.theme.erase("grain")
		settings.theme["rev"] = 3
	if int(settings.theme.get("rev", 1)) < 4:
		# 0.5: Graphit Gold mit Hanken Grotesk und weichen Ecken. Eigene Schriften und
		# Schemata bleiben, nur die alten Standardwerte werden ersetzt.
		if str(settings.theme.get("font", "")) == "atkinson":
			settings.theme["font"] = "hanken"
		if str(settings.theme.get("display", "")) == "saira":
			settings.theme["display"] = "hanken"
		if str(settings.theme.get("corners", "")) == "leicht":
			settings.theme["corners"] = "rund"
		settings.theme["rev"] = 4
	if int(settings.theme.get("rev", 1)) < 5:
		# 0.5.2: Halten und Stick ruhiger. Wer die alten Standardwerte hatte, bekommt die neuen.
		var c: Dictionary = settings.controller
		if absf(float(c.get("repeat_delay", 0.4)) - 0.32) < 0.001:
			c["repeat_delay"] = 0.4
		if float(c.get("repeat_rate", 0.12)) < 0.1:
			c["repeat_rate"] = 0.12
		if absf(float(settings.theme.get("sound_volume", 0.6)) - 0.7) < 0.001:
			settings.theme["sound_volume"] = 0.6
		settings.theme["rev"] = 5
	if int(settings.theme.get("rev", 1)) < 6:
		# 0.7: Reihenfolge nach Nutzen – Spiele, Shop, Erfolge, Freunde, Musik, Videos. Wer die
		# alte Standard-Reihenfolge hatte (nie selbst sortiert), bekommt die neue.
		var old := ["games", "videos", "achievements", "friends", "music", "shop", "settings"]
		var mine: Array = settings.theme.get("sections", [])
		if mine.is_empty() or mine == old:
			settings.theme["sections"] = (DEFAULTS.theme.sections as Array).duplicate()
		settings.theme["rev"] = 6
	if int(settings.theme.get("rev", 1)) < 7:
		# 0.7.1: Videos liegen vorn (mpv zeichnet Uzais Leiste selbst). Das durchsichtige Fenster
		# darüber blieb auf vielen PCs schwarz; wer es will, stellt es unter Videos wieder um.
		if str(settings.youtube.get("display", "")) == "overlay":
			settings.youtube["display"] = "mpv"
		settings.theme["rev"] = 7
	if int(settings.theme.get("rev", 1)) < 8:
		# Gesamtaufbau (docs/AUFBAU.md): Spiele, Medien, Social, Shop. Wer die alte Standard-
		# Reihenfolge hatte (nie selbst sortiert), bekommt die neue.
		var old := ["games", "shop", "achievements", "friends", "music", "videos", "movies", "streams", "settings"]
		var mine: Array = settings.theme.get("sections", [])
		if mine.is_empty() or mine == old:
			settings.theme["sections"] = (DEFAULTS.theme.sections as Array).duplicate()
		settings.theme["rev"] = 8
	if int(settings.theme.get("rev", 1)) < 9:
		# Themes (Punkte 37, 60, 61): Das bisherige Aussehen ist das eingebaute Theme „Graphit“.
		# Wer die bisherigen Standardwerte hatte, folgt jetzt dem Theme („theme“) – sieht mit
		# Graphit genau gleich aus. Eigene Wahl (anderes Farbschema, eckig, Atkinson …) bleibt.
		var th: Dictionary = settings.theme
		for kv in [["preset", "uzai"], ["corners", "rund"], ["font", "hanken"], ["display", "hanken"],
				["cover_shape", "hoch"], ["cover_size", "m"], ["background", "game"], ["boot", "voll"]]:
			if str(th.get(kv[0], "")) == kv[1]:
				th[kv[0]] = "theme"
		th["rev"] = 9
	if int(settings.theme.get("rev", 1)) < 10:
		# Leiste, wie der Nutzer sie will: Spiele, Shop, Freunde, Profil, Apps, Einstellungen. Musik,
		# Videos, Filme, Streams (und Zimmer) sind Apps; „Medien zusammenfassen“ (group_media) gibt
		# es nicht mehr. Ausgeblendete Bereiche bleiben ausgeblendet – Apps unter „Apps“.
		var th: Dictionary = settings.theme
		th.erase("group_media")
		th["sections"] = (DEFAULTS.theme.sections as Array).duplicate()
		var hid: Array = th.get("hidden_sections", []) if th.get("hidden_sections") is Array else []
		var apps_hid: Array = []
		for k in ["music", "videos", "movies", "streams", "room"]:
			if hid.has(k):
				apps_hid.append(k)
		th["hidden_sections"] = hid.filter(func(x: Variant) -> bool: return not apps_hid.has(x) and str(x) != "media")
		if not apps_hid.is_empty():
			settings.apps["hidden"] = apps_hid
		th["rev"] = 10
	# Themes gibt es nicht mehr: Die alte Wahl fällt still weg. „Startanimation je System“
	# kannte „an“ neben „Vom Theme“ – beides heißt jetzt Standard.
	(settings.theme as Dictionary).erase("pack")
	if str((settings.theme as Dictionary).get("system_intro", "")) == "an":
		settings.theme["system_intro"] = "theme"
	if int((saved.get("badges", {}) as Dictionary).get("rev", 1) if saved.get("badges") is Dictionary else 1) < 2:
		# Echte Konsolen-Logos sind jetzt Standard (Startseite, Abzeichen). Ein früheres „aus“ war
		# der alte Standard – einmal auf „an“; danach gilt die eigene Wahl.
		(settings.badges as Dictionary)["real_logos"] = true
		(settings.badges as Dictionary)["rev"] = 2
	_klangsatz_umstellen()
	_migrate(old_schema)
	var changed := old_schema != int(settings.schema) or old_version != VERSION
	settings["uzai_version"] = VERSION
	# Der Name des Profils ist der Spielername (Guide, Begrüßung).
	var me := profile()
	if not me.is_empty():
		(settings.system as Dictionary)["player_name"] = str(me.name)
	if (changed or repaired) and not saved.is_empty():
		save_settings()
	Backup.snapshot_settings(own_dir)
	Backup.snapshot_settings(data_dir, -1, "gemeinsam")


## Neuer Standard-Klangsatz: wer den alten Standard hatte, bekommt einmal den neuen; die alten Sätze
## bleiben wählbar, eine andere eigene Wahl bleibt (theme.rev 11 bis 14).
func _klangsatz_umstellen() -> void:
	var th: Dictionary = settings.theme
	if int(th.get("rev", 1)) < 11:
		# 0.12: „Filz & Glas“ statt „Glas“ (Tick, Filz … bleiben).
		if str(th.get("sound_set", "")) == "glas":
			th["sound_set"] = "filzglas"
		th["rev"] = 11
	if int(th.get("rev", 1)) < 12:
		# „Perle“ (tools/synth_klang3.py) statt „Filz & Glas“ (Glas, Tick, Filz … bleiben).
		if str(th.get("sound_set", "")) == "filzglas":
			th["sound_set"] = "perle"
		th["rev"] = 12
	if int(th.get("rev", 1)) < 13:
		# „Samt“ (tools/synth_klang4.py: weich, leise, dunkel) statt „Perle“ (Perle, Kiesel, Pad … bleiben).
		if str(th.get("sound_set", "")) == "perle":
			th["sound_set"] = "samt"
		th["rev"] = 13
	if int(th.get("rev", 1)) < 14:
		# „Handpan“ (tools/synth_klang5.py: tiefe, weiche Handpan) statt „Samt“ (Samt, Perle, Kiesel … bleiben).
		if str(th.get("sound_set", "")) == "samt":
			th["sound_set"] = "handpan"
		th["rev"] = 14


## Einstellungen von schema bis SETTINGS_VERSION umstellen. Neuere Stände (von einer neueren
## Uzai-Version) bleiben, wie sie sind – unbekannte Werte gehen nicht verloren.
func _migrate(from_schema: int) -> void:
	if from_schema > SETTINGS_VERSION:
		notices.append("Deine Einstellungen stammen von einer neueren Uzai-Version. Uzai lässt sie, wie sie sind.")
		return
	for v in range(from_schema, SETTINGS_VERSION):
		match v:
			0:
				# Einführung der Versionsnummer: alles Ältere stellen die theme.rev-Schritte um.
				pass
			1:
				# Guide-Taste halten (Punkt 21): rest.hold_guide (an/aus) wird controller.guide_hold.
				# Wer das Halten ausgeschaltet hatte, behält es aus; sonst gibt es das Schnellmenü,
				# in dem der Ruhemodus mit einem Druck bleibt.
				var r: Variant = settings.get("rest")
				if r is Dictionary and (r as Dictionary).has("hold_guide"):
					if not bool(r.hold_guide):
						(settings.controller as Dictionary)["guide_hold"] = "aus"
					(r as Dictionary).erase("hold_guide")
			2:
				# Rest mode no longer turns the screen off (TVs lost the signal and renegotiated VRR);
				# it shows the rest screen instead.
				var r2: Variant = settings.get("rest")
				if r2 is Dictionary:
					(r2 as Dictionary)["screen_off"] = false
			3:
				# Browser: Google is the default search engine. Settings with the old default DuckDuckGo switch to
				# Google; any other search engine the user picked is kept.
				var b: Variant = settings.get("browser")
				if b is Dictionary and str((b as Dictionary).get("suche", "")) == "duckduckgo":
					(b as Dictionary)["suche"] = "google"
	settings["schema"] = SETTINGS_VERSION


## Werte mit falschem Typ (von Hand geändert, ältere oder neuere Uzai-Version) auf den Standard
## setzen. Sonst brach etwa ein Text statt einer Liste den Aufbau ab – die Oberfläche blieb leer.
static func sanitize(value: Dictionary, defaults: Dictionary, prefix := "") -> void:
	for k in defaults.keys():
		if not value.has(k):
			continue
		var d: Variant = defaults[k]
		var v: Variant = value[k]
		var bad := false
		if Vault.is_sealed(v):
			continue
		if d is Dictionary:
			if v is Dictionary:
				sanitize(v, d, prefix + str(k) + ".")
			else:
				bad = true
		elif d is Array:
			bad = not (v is Array)
		elif d is bool:
			bad = not (v is bool)
		elif d is int or d is float:
			bad = not (v is int or v is float)
		elif d is String:
			bad = not (v is String)
		if bad:
			push_warning("Uzai: Einstellung %s%s hatte einen falschen Typ, nehme den Standard" % [prefix, k])
			value[k] = d.duplicate(true) if (d is Dictionary or d is Array) else d


func save_settings() -> void:
	# Ohne Schlüssel nicht offen schreiben: warten, bis er da ist (_process).
	if (_vault_job != null and _vault_job.is_alive()) or (_shared_job != null and _shared_job.is_alive()):
		_save_waiting = true
		set_process(true)
		return
	# Gemeinsames für alle Profile, der Rest (samt versiegelter Anmeldungen) ins eigene Profil.
	var parts := Profiles.split_settings(_sealed_settings())
	write_json(shared_path(Profiles.SHARED_FILE), parts[0], "\t")
	write_json(path("settings.json"), parts[1], "\t")


func _process(_dt: float) -> void:
	if (_vault_job != null and _vault_job.is_alive()) or (_shared_job != null and _shared_job.is_alive()):
		return
	set_process(false)
	if _save_waiting:
		_save_waiting = false
		save_settings()


## Wie die Anmeldungen geschützt sind: "dpapi", "test" oder "" (Einstellungen → System).
func vault_state() -> String:
	_keys()
	return vault_how


## Schlüssel des Tresors (wartet beim ersten Mal auf den Faden).
func _keys() -> Array:
	if _vault_job != null:
		var r: Dictionary = _vault_job.wait_to_finish()
		_vault_job = null
		_vault_keys = r.get("keys", [])
		vault_how = str(r.get("how", ""))
		if str(r.get("error", "")) != "":
			push_warning("Uzai: Tresor – " + str(r.error))
	return _vault_keys


## Schlüssel des gemeinsamen Tresors (ohne Profile: dieselben wie _keys()).
func _shared_keys() -> Array:
	if _shared_job != null:
		var r: Dictionary = _shared_job.wait_to_finish()
		_shared_job = null
		_shared_keys_list = r.get("keys", [])
		if str(r.get("error", "")) != "":
			push_warning("Uzai: gemeinsamer Tresor – " + str(r.error))
	return _shared_keys_list if profile_dir != "" else _keys()


## Alle Schlüssel zum Öffnen: erst die des Profils, dann die gemeinsamen.
func _open_keys() -> Array:
	var out := _keys().duplicate()
	for k in _shared_keys():
		if not out.has(k):
			out.append(k)
	return out


## Geheimes, das für alle Profile gilt (Profiles.SHARED nennt es).
static func shared_secret(p: String) -> bool:
	return p in Vault.SECRETS and p in Profiles.SHARED_SECRETS


## Einstellungen zum Speichern: Geheimes versiegelt. Ohne Schlüssel bleibt Versiegeltes, wie es
## ist, und Neues steht offen drin wie früher (Einstellungen → System sagt das). Gemeinsames
## Geheimes (shared_secret) kommt in den gemeinsamen Tresor – auch, was noch mit dem Schlüssel
## eines Profils versiegelt ist (einmalige Übernahme aus der Zeit vor dem gemeinsamen Schlüssel).
func _sealed_settings() -> Dictionary:
	var keys := _keys()
	if keys.is_empty():
		return settings
	var out := settings.duplicate(true)
	var shared_keys := _shared_keys()
	for p in Vault.SECRETS:
		var v: Variant = _raw(out, p)
		if v == null or (v is String and v == ""):
			continue
		if shared_secret(p) and not shared_keys.is_empty():
			if Vault.is_sealed(v) and Vault.open(v, shared_keys) != null:
				continue
			var plain: Variant = Vault.open(v, _open_keys()) if Vault.is_sealed(v) else v
			if plain != null:
				_put_raw(out, p, Vault.seal(plain, shared_keys[0]))
			continue
		if Vault.is_sealed(v):
			continue
		_put_raw(out, p, Vault.seal(v, keys[0]))
	return out


static func _raw(d: Dictionary, key_path: String) -> Variant:
	var node: Variant = d
	for part in key_path.split("."):
		if not (node is Dictionary and node.has(part)):
			return null
		node = node[part]
	return node


## Wie _put_raw, legt fehlende Abschnitte an.
static func _put_path(d: Dictionary, key_path: String, v: Variant) -> void:
	var parts := key_path.split(".")
	var node: Dictionary = d
	for i in parts.size() - 1:
		if not (node.get(parts[i]) is Dictionary):
			node[parts[i]] = {}
		node = node[parts[i]]
	node[parts[parts.size() - 1]] = v


static func _put_raw(d: Dictionary, key_path: String, v: Variant) -> void:
	var parts := key_path.split(".")
	var node: Dictionary = d
	for i in parts.size() - 1:
		node = node[parts[i]]
	node[parts[parts.size() - 1]] = v


func save_soon() -> void:
	if _save_timer:
		_save_timer.start()
	else:
		save_settings()


## Land für Preise und Angebote (Steam-Shop, Warenkorb, Epic): die Einstellung „system.country“,
## bei „auto“ nach Sprache und Windows (Lang.land_fuer). Zwei Großbuchstaben, etwa „DE“.
func land() -> String:
	return Lang.land_fuer(str(get_value("system.country", "auto")), TranslationServer.get_locale(), OS.get_locale())


## Währung dieses Landes („EUR“, „USD“ …).
func waehrung() -> String:
	return Lang.waehrung_fuer(land())


func get_value(key_path: String, fallback: Variant = null) -> Variant:
	if safe_mode and SAFE.has(key_path):
		return SAFE[key_path]
	if _temp.has(key_path):
		return _temp[key_path]
	var node: Variant = settings
	for part in key_path.split("."):
		if node is Dictionary and node.has(part):
			node = node[part]
		else:
			return fallback
	if Vault.is_sealed(node):
		# Erst beim ersten Gebrauch öffnen; danach liegt der Wert offen im Speicher.
		var plain: Variant = Vault.open(node, _open_keys())
		if plain == null:
			return fallback
		_put_raw(settings, key_path, plain)
		return passend(plain, fallback)
	return passend(node, fallback)


## Der Ersatzwert sagt auch, welche Art Wert der Aufrufer erwartet. Steht in der Datei etwas anderes (von Hand
## geändert, andere Uzai-Fassung), gilt der Ersatzwert: bool("text"), „as Array“ oder eine Zuweisung mit Typ
## brächen sonst die Funktion des Aufrufers ab. sanitize() fängt das nur für Schlüssel aus DEFAULTS ab; viele
## Einstellungen stehen dort nicht. Ein Text oder null als Ersatzwert prüft nichts (gelesen wird mit str()).
static func passend(wert: Variant, fallback: Variant) -> Variant:
	match typeof(fallback):
		TYPE_BOOL:
			return wert if wert is bool else fallback
		TYPE_INT, TYPE_FLOAT:
			return wert if (wert is int or wert is float) else fallback
		TYPE_ARRAY:
			return wert if wert is Array else fallback
		TYPE_DICTIONARY:
			return wert if wert is Dictionary else fallback
	return wert


func set_value(key_path: String, value: Variant) -> void:
	var parts := key_path.split(".")
	var node: Dictionary = settings
	for i in parts.size() - 1:
		var part := parts[i]
		if not (node.get(part) is Dictionary):
			node[part] = {}
		node = node[part]
	node[parts[parts.size() - 1]] = value
	# Selbst umgestellt (etwa im Guide während des Spiels): die eigene Wahl gilt ab sofort.
	_temp.erase(key_path)
	_forget_merged(parts[0])
	save_soon()
	changed.emit(key_path)
	# Der Spielername ist der Name des Profils (etwa aus der Einrichtung gesetzt).
	if key_path == "system.player_name" and profile_id != "":
		var n := Profiles.clean_name(value)
		if n != "" and n != str(profile().get("name", "")):
			update_profile(profile_id, { "name": n })


## Vorübergehend ein anderer Wert, solange ein Spiel mit Profil läuft (src/core/profile_run.gd).
## get_value liefert ihn, gespeichert wird er nie; set_value auf denselben Schlüssel nimmt ihn
## zurück. Nur einzelne Werte (Blätter), keine ganzen Abschnitte.
func set_temp(key_path: String, value: Variant) -> void:
	_temp[key_path] = value
	changed.emit(key_path)


func clear_temp() -> void:
	var keys := _temp.keys()
	_temp.clear()
	for k in keys:
		changed.emit(str(k))


func has_temp(key_path: String) -> bool:
	return _temp.has(key_path)


func _forget_merged(kind := "") -> void:
	if kind == "":
		_merged.clear()
		_merged_by.clear()
	elif kind in ["systems", "emulators", "filters"]:
		_merged.erase(kind)
		_merged_by.erase(kind)


# --- Systeme, Emulatoren, Filter ---------------------------------------------

func _load_base_data() -> void:
	var s: Variant = read_json("res://data/systems.json", {})
	_base_systems = s.get("systems", []) if s is Dictionary else []
	var e: Variant = read_json("res://data/emulators.json", {})
	_base_emulators = e.get("emulators", []) if e is Dictionary else []
	var f: Variant = read_json("res://data/filters.json", {})
	_base_filters = f.get("filters", []) if f is Dictionary else []
	_forget_merged()


func systems() -> Array:
	if not _merged.has("systems"):
		_remember_merged("systems", _merge_systems())
	return (_merged.systems as Array).duplicate()


func _remember_merged(kind: String, list: Array) -> void:
	_merged[kind] = list
	var by := {}
	for x in list:
		if x is Dictionary and not by.has(str(x.get("id", ""))):
			by[str(x.get("id", ""))] = x
	_merged_by[kind] = by


func _merge_systems() -> Array:
	var out: Array = []
	var over: Dictionary = settings.get("systems", {})
	for base in _base_systems:
		var sys: Dictionary = base.duplicate(true)
		if over.get(sys.id) is Dictionary:
			sys = deep_merge(sys, over[sys.id])
			sanitize(sys, base, "systems.%s." % sys.id)
		out.append(sys)
	for id in over.keys():
		if over[id] is Dictionary and over[id].get("custom", false) and not out.any(func(x): return x.id == id):
			var c: Dictionary = over[id].duplicate(true)
			c["id"] = id
			out.append(c)
	return out


func systems_enabled() -> Array:
	return systems().filter(func(s): return s.get("enabled", false))


func system(id: String) -> Dictionary:
	if not _merged.has("systems"):
		systems()
	return (_merged_by.systems as Dictionary).get(id, {})


func set_system(id: String, key: String, value: Variant) -> void:
	set_value("systems.%s.%s" % [id, key], value)


func emulators() -> Array:
	if not _merged.has("emulators"):
		_remember_merged("emulators", _merge_emulators())
	return (_merged.emulators as Array).duplicate()


func _merge_emulators() -> Array:
	var out: Array = []
	var over: Dictionary = settings.get("emulators", {})
	for base in _base_emulators:
		var emu: Dictionary = base.duplicate(true)
		if over.get(emu.id) is Dictionary:
			emu = deep_merge(emu, over[emu.id])
			sanitize(emu, base, "emulators.%s." % emu.id)
		out.append(emu)
	# Eigene Emulatoren, die der Nutzer angelegt hat
	for id in over.keys():
		if over[id] is Dictionary and over[id].get("custom", false) and not over[id].get("deleted", false):
			var c: Dictionary = over[id].duplicate(true)
			c["id"] = id
			out.append(c)
	return out


## Neuer, eigener Emulator – leer oder als Kopie einer Vorlage. Gibt die neue ID zurück.
func add_emulator(name: String, template_id := "") -> String:
	var base := emulator(template_id) if template_id != "" else {}
	var id := "eigen_%d" % int(Time.get_unix_time_from_system() * 10.0)
	var e := {
		"custom": true, "name": name,
		"systems": (base.get("systems", []) as Array).duplicate(),
		"args": str(base.get("args", "\"{rom}\"")),
		"keys": (base.get("keys", { "save": "", "load": "", "screenshot": "" }) as Dictionary).duplicate(),
		"window_hint": str(base.get("window_hint", name)),
		"exe_hint": str(base.get("exe_hint", "")), "exe": str(base.get("exe", "")),
	}
	set_value("emulators.%s" % id, e)
	return id


func delete_emulator(id: String) -> void:
	var over: Dictionary = settings.get("emulators", {})
	if not (over.get(id) is Dictionary) or not over[id].get("custom", false):
		return
	over.erase(id)
	_forget_merged("emulators")
	for sys in systems():
		if str(sys.get("emulator", "")) == id:
			set_system(str(sys.id), "emulator", "")
	save_soon()
	changed.emit("emulators")


## Alles, was delete_emulator wegnimmt – der eigene Emulator und welche Systeme ihn nutzen –, damit
## Rückgängig (src/core/undo.gd) es mit restore_emulator genau zurückholen kann.
func emulator_backup(id: String) -> Dictionary:
	var over: Dictionary = settings.get("emulators", {})
	var used: Array = []
	for sys in systems():
		if str(sys.get("emulator", "")) == id:
			used.append(str(sys.id))
	return { "id": id, "data": (over.get(id, {}) as Dictionary).duplicate(true) if over.get(id) is Dictionary else {}, "systems": used }


func restore_emulator(back: Dictionary) -> void:
	var id := str(back.get("id", ""))
	if id == "" or not (back.get("data") is Dictionary) or (back.data as Dictionary).is_empty():
		return
	set_value("emulators.%s" % id, (back.data as Dictionary).duplicate(true))
	for sid in back.get("systems", []):
		set_system(str(sid), "emulator", id)


func emulator(id: String) -> Dictionary:
	if not _merged.has("emulators"):
		emulators()
	return (_merged_by.emulators as Dictionary).get(id, {})


func emulators_for(system_id: String) -> Array:
	return emulators().filter(func(e): return system_id in e.get("systems", []))


func set_emulator(id: String, key: String, value: Variant) -> void:
	set_value("emulators.%s.%s" % [id, key], value)


func filters() -> Array:
	if not _merged.has("filters"):
		_remember_merged("filters", _merge_filters())
	return (_merged.filters as Array).duplicate()


func _merge_filters() -> Array:
	var out: Array = []
	var over: Dictionary = settings.get("filters", {})
	for base in _base_filters:
		var flt: Dictionary = base.duplicate(true)
		if over.get(flt.id) is Dictionary:
			flt = deep_merge(flt, over[flt.id])
			sanitize(flt, base, "filters.%s." % flt.id)
		out.append(flt)
	return out


func filter(id: String) -> Dictionary:
	if not _merged.has("filters"):
		filters()
	return (_merged_by.filters as Dictionary).get(id, {})


func rom_dir(system_id: String) -> String:
	return str(get_value("library.rom_dirs", {}).get(system_id, ""))


func set_rom_dir(system_id: String, dir: String) -> void:
	var dirs: Dictionary = get_value("library.rom_dirs", {}).duplicate()
	dirs[system_id] = dir
	set_value("library.rom_dirs", dirs)


func media_dir() -> String:
	var d := str(get_value("library.media_dir", ""))
	return d if d != "" else path("media")


## Test-Umleitungen kommen aus Umgebungsvariablen UZAI_…: Adressen der Dienste auf nachgebaute Server, ein anderer
## Helfer, eine andere JavaScript-Laufzeit für Plugins, http zu diesem PC. Im ausgelieferten Programm (Export
## „Release“) gelten sie nicht: Eine gesetzte Variable schickte sonst Anmeldungen an eine fremde Adresse oder ließe
## Plugins ohne Absicherung laufen. Nur Entwickler-Fassungen lesen sie (Editor, Tests, Debug-Export).
## entwickler: nur für den Test dieser Regel. Der Datenordner (UZAI_DATA) ist keine Umleitung und bleibt.
static func probe_env(name: String, entwickler := OS.is_debug_build()) -> String:
	return OS.get_environment(name) if entwickler else ""


func is_windows() -> bool:
	return OS.get_name() == "Windows"


# --- Profile (Roadmap 109, src/core/profiles.gd) ----------------------------------------------

## Profile lesen bzw. beim ersten Start mit Profilen anlegen und das Profil dieses Laufs wählen:
## --profil=<id> (nach einem Wechsel), sonst das zuletzt gewählte.
func _setup_profiles() -> void:
	profiles = Profiles.read_file(data_dir)
	if (profiles.profiles as Array).is_empty():
		_first_profiles()
	var want := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profil="):
			want = a.substr(9)
		elif a == "--profilwechsel":
			profile_welcome = true
	if Profiles.valid_id(want) and not Profiles.find(profiles, want).is_empty():
		profile_id = want
		profile_chosen = true
	elif not Profiles.find(profiles, str(profiles.last)).is_empty():
		profile_id = str(profiles.last)
	else:
		profile_id = str(profiles.profiles[0].id)
	profile_dir = Profiles.dir_of(data_dir, profile_id)
	DirAccess.make_dir_recursive_absolute(profile_dir)
	_adopt_legacy()
	if str(profiles.last) != profile_id:
		profiles.last = profile_id
		Profiles.write_file(data_dir, profiles)


## Noch keine (lesbare) profiles.json: Ordner vorhandener Profile wiederfinden, sonst das erste
## Profil anlegen. Gibt es schon Daten (Einzelnutzer-Stand), wird vorher alles gesichert; der Stand
## wird dann das erste Profil (_adopt_legacy).
func _first_profiles() -> void:
	var found: Array = []
	var pdir := data_dir.path_join(Profiles.DIR)
	if DirAccess.dir_exists_absolute(pdir):
		for id in DirAccess.get_directories_at(pdir):
			if Profiles.valid_id(id) and found.size() < Profiles.MAX_PROFILES:
				var st: Variant = read_json(pdir.path_join(id).path_join("settings.json"), null)
				if not (st is Dictionary):
					st = Backup.latest_settings(pdir.path_join(id)).get("data", null)
				var n := ""
				if st is Dictionary and st.get("system") is Dictionary:
					n = Profiles.clean_name(st.system.get("player_name", ""))
				found.append(Profiles.clean_profile({ "id": id, "name": n if n != "" else "Profil %d" % (found.size() + 1),
					"color": Profiles.COLORS[found.size() % Profiles.COLORS.size()][0] }))
	if not found.is_empty():
		profiles.profiles = found
		profiles.legacy = str(found[0].id)
		profiles.last = str(found[0].id)
		Profiles.write_file(data_dir, profiles)
		notices.append("Die Liste der Profile war beschädigt. Uzai hat %d Profile aus ihren Ordnern wiederhergestellt." % found.size())
		return
	var legacy := FileAccess.file_exists(data_dir.path_join("settings.json")) or FileAccess.file_exists(data_dir.path_join("library.json"))
	var name := "Spieler 1"
	if legacy:
		var b := Backup.create(data_dir, "vor-profilen")
		if not bool(b.ok):
			push_warning("Uzai: Sicherung vor den Profilen ging nicht: " + str(b.error))
		var old: Variant = read_json(data_dir.path_join("settings.json"), null)
		if old is Dictionary and old.get("system") is Dictionary:
			var n2 := Profiles.clean_name(old.system.get("player_name", ""))
			if n2 != "":
				name = n2
	var p := Profiles.make_profile(name, [], str(Profiles.COLORS[0][0]))
	profiles.profiles = [p]
	profiles.legacy = str(p.id)
	profiles.last = str(p.id)
	Profiles.write_file(data_dir, profiles)
	if legacy:
		notices.append("Uzai hat jetzt Profile. Dein bisheriger Stand ist dein Profil „%s“ – vorher gesichert." % name)


## Altbestand (Stand vor den Profilen, auch aus einer alten Sicherung zurückgeholt) gehört dem
## ersten Profil: settings.json im Hauptordner wird zu gemeinsam.json und dessen settings.json,
## seine Dateien (Verlauf, Zimmer …) und Tresor-Schlüssel ziehen in seinen Ordner. Die Bibliothek
## trennt ihre persönlichen Felder selbst (Library.load_library).
func _adopt_legacy() -> void:
	var owner := legacy_owner()
	var odir := Profiles.dir_of(data_dir, owner)
	if odir == "":
		return
	DirAccess.make_dir_recursive_absolute(odir)
	var old_p := data_dir.path_join("settings.json")
	if FileAccess.file_exists(old_p) or FileAccess.file_exists(old_p + ".bak"):
		var old: Variant = read_json(old_p, null)
		var ok := true
		if old is Dictionary:
			var parts := Profiles.split_settings(old)
			ok = write_json(data_dir.path_join(Profiles.SHARED_FILE), parts[0], "\t") and write_json(odir.path_join("settings.json"), parts[1], "\t")
		if ok:
			for f in [old_p, old_p + ".bak", old_p + ".tmp"]:
				DirAccess.remove_absolute(f)
	for rel in Profiles.OWN_FILES:
		if rel == "settings.json":
			continue
		for ext in ["", ".bak"]:
			var f := data_dir.path_join(rel + ext)
			if not FileAccess.file_exists(f):
				continue
			if rel in Profiles.DROP_CACHES:
				DirAccess.remove_absolute(f)
			else:
				_move_file(f, odir.path_join(rel + ext))
	var top := DirAccess.open(data_dir)
	for d in Profiles.OWN_DIRS:
		var dn := str(d).trim_suffix("/")
		var sd := data_dir.path_join(dn)
		if top != null and DirAccess.dir_exists_absolute(sd) and not top.is_link(dn):
			_move_tree(sd, odir.path_join(dn), 0)
	for k in Profiles.KEY_FILES:
		var src2 := data_dir.path_join(k)
		if FileAccess.file_exists(src2) and not FileAccess.file_exists(odir.path_join(k)):
			_move_file(src2, odir.path_join(k))


func _move_file(src: String, dest: String) -> void:
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)
	if DirAccess.rename_absolute(src, dest) != OK and DirAccess.copy_absolute(src, dest) == OK:
		DirAccess.remove_absolute(src)


## Ordner verschieben (nur echte Dateien und Ordner, keine Verknüpfungen), leere Reste weg.
func _move_tree(src: String, dest: String, depth: int) -> void:
	var da := DirAccess.open(src)
	if da == null or depth > 8:
		return
	for f in da.get_files():
		if not da.is_link(f):
			_move_file(src.path_join(f), dest.path_join(f))
	for sub in da.get_directories():
		if not da.is_link(sub):
			_move_tree(src.path_join(sub), dest.path_join(sub), depth + 1)
	DirAccess.remove_absolute(src)


## Wem der Stand vor den Profilen gehört: dem ersten Profil (gibt es das nicht mehr, dem ersten
## in der Liste).
func legacy_owner() -> String:
	if not Profiles.find(profiles, str(profiles.get("legacy", ""))).is_empty():
		return str(profiles.legacy)
	var list: Array = profiles.get("profiles", [])
	return str(list[0].id) if not list.is_empty() else ""


## Das aktive Profil ({ id, name, color, avatar, kid, rules, pin? }).
func profile() -> Dictionary:
	return Profiles.find(profiles, profile_id)


func profile_list() -> Array:
	return profiles.get("profiles", [])


## Beim Start „Wer spielt?“ zeigen: nur mit mehr als einem Profil und ohne Wahl per Startargument.
func needs_picker() -> bool:
	return profile_list().size() > 1 and not profile_chosen


func is_kid() -> bool:
	return bool(profile().get("kid", false))


func kid_rules() -> Dictionary:
	return profile().get("rules", {}) if is_kid() else {}


## Kinderprofil: ist das ausgeschaltet? what: "shop", "browser", "chats".
func kid_blocks(what: String) -> bool:
	return is_kid() and not bool(kid_rules().get(what, false))


## Kinderprofil: ist das aus, sagt Uzai es freundlich und gibt true zurück (dann nichts tun).
func kid_stop(what: String) -> bool:
	if not kid_blocks(what):
		return false
	var t: String = { "shop": "Der Shop ist in diesem Profil aus.", "browser": "Webseiten öffnet Uzai in diesem Profil nicht.",
		"chats": "Chats und Sprachkanäle sind in diesem Profil aus." }.get(what, "Das ist in diesem Profil aus.")
	Toasts.show_toast("Kinderprofil", t, "lock")
	return true


## Kinderprofil: Spiel über der Altersstufe (oder ohne Angabe, wenn so eingestellt).
func kid_hides(g: Dictionary) -> bool:
	return is_kid() and not Profiles.age_allowed(kid_rules(), g)


func save_profiles() -> void:
	profiles = Profiles.clean_file(profiles)
	Profiles.write_file(data_dir, profiles)
	profiles_changed.emit()


## Neues Profil. {} wenn es schon MAX_PROFILES gibt oder der Name leer ist.
func add_profile(name: String, color := "", avatar := "buchstabe") -> Dictionary:
	var n := Profiles.clean_name(name)
	if n == "" or profile_list().size() >= Profiles.MAX_PROFILES:
		return {}
	var p := Profiles.make_profile(n, Profiles.ids(profiles), color, avatar)
	if p.is_empty():
		return {}
	(profiles.profiles as Array).append(p)
	save_profiles()
	DirAccess.make_dir_recursive_absolute(Profiles.dir_of(data_dir, str(p.id)))
	return p


## Profil ändern: name, color, avatar, kid, rules, pin (Hash aus Profiles.make_pin; {} = ohne PIN).
func update_profile(id: String, changes: Dictionary) -> bool:
	var list: Array = profiles.get("profiles", [])
	for i in list.size():
		if str(list[i].id) != id:
			continue
		var p: Dictionary = (list[i] as Dictionary).duplicate(true)
		for k in ["name", "color", "avatar", "kid", "rules"]:
			if changes.has(k):
				p[k] = changes[k]
		if changes.has("pin"):
			if changes.pin is Dictionary and not (changes.pin as Dictionary).is_empty():
				p["pin"] = changes.pin
			else:
				p.erase("pin")
			(profiles.brake as Dictionary).erase(id)
		var c := Profiles.clean_profile(p)
		if c.is_empty():
			return false
		list[i] = c
		save_profiles()
		if id == profile_id and str(c.name) != str(get_value("system.player_name", "")):
			set_value("system.player_name", str(c.name))
		return true
	return false


## Profil löschen: nur ein anderes als das aktive, nie das letzte. Löscht nur seinen eigenen
## Ordner (profiles/<id>) – nie über Verknüpfungen. { ok, text }
func delete_profile(id: String) -> Dictionary:
	if id == profile_id:
		return { "ok": false, "text": "Das gerade aktive Profil lässt sich nicht löschen. Wechsle vorher in ein anderes." }
	if profile_list().size() <= 1 or Profiles.find(profiles, id).is_empty():
		return { "ok": false, "text": "Dieses Profil gibt es nicht (mehr)." }
	var r := Profiles.delete_dir(data_dir, id)
	profiles.profiles = profile_list().filter(func(p: Dictionary) -> bool: return str(p.id) != id)
	(profiles.brake as Dictionary).erase(id)
	if str(profiles.legacy) == id:
		profiles.legacy = ""
	if str(profiles.last) == id:
		profiles.last = profile_id
	save_profiles()
	if not bool(r.ok):
		return { "ok": true, "text": "Profil entfernt. %d Dateien ließen sich nicht löschen (Verknüpfungen bleiben immer unangetastet)." % int(r.left) }
	return { "ok": true, "text": "" }


## Bremse für PIN-Versuche (bleibt über einen Neustart erhalten). ids: die Profile, deren PIN
## gilt (bei der Eltern-PIN alle Erwachsenen mit PIN) – es zählt die längste Wartezeit.
func pin_wait(ids: Array) -> int:
	var now := int(Time.get_unix_time_from_system())
	var w := 0
	for id in ids:
		w = maxi(w, Profiles.brake_wait((profiles.brake as Dictionary).get(id, {}), now))
	return w


func pin_tries_left(ids: Array) -> int:
	var n := Profiles.BRAKE_FREE
	for id in ids:
		n = mini(n, Profiles.brake_left((profiles.brake as Dictionary).get(id, {})))
	return n


func pin_result(ids: Array, ok: bool) -> void:
	var now := int(Time.get_unix_time_from_system())
	var dirty := false
	for id in ids:
		if ok:
			dirty = dirty or (profiles.brake as Dictionary).has(id)
			(profiles.brake as Dictionary).erase(id)
		elif not Profiles.find(profiles, str(id)).is_empty():
			profiles.brake[id] = Profiles.brake_fail((profiles.brake as Dictionary).get(id, {}), now)
			dirty = true
	if dirty:
		Profiles.write_file(data_dir, profiles)


## Erwachsene Profile mit PIN (für die Eltern-PIN eines Kinderprofils).
func parent_ids() -> Array:
	return profile_list().filter(func(p: Dictionary) -> bool: return not bool(p.kid) and p.has("pin")).map(func(p: Dictionary) -> String: return str(p.id))


## Braucht diese Handlung eine PIN? "" nein, "target" die des Profils, "parent" eine Eltern-PIN,
## "no" geht gar nicht (Profiles.guard).
func profile_guard(action: String, target_id: String) -> String:
	return Profiles.guard(action, profile(), Profiles.find(profiles, target_id), not parent_ids().is_empty())


## Spielzeit eines Kinderprofils heute (kind.json im Ordner des Profils).
func kid_time() -> Dictionary:
	return Profiles.clean_time(Profiles.read_small_json(path("kind.json"), 4096))


func kid_time_add(secs: int) -> void:
	if not is_kid() or secs <= 0:
		return
	write_json(path("kind.json"), Profiles.time_add(kid_time(), kid_today(), secs))


## Eltern geben mehr Zeit: so viele Minuten zählen heute nicht mehr.
func kid_time_bonus(minutes: int) -> void:
	var st := kid_time()
	var used := Profiles.time_used(st, kid_today())
	write_json(path("kind.json"), { "day": kid_today(), "secs": maxi(0, used - maxi(minutes, 0) * 60) })


func kid_today() -> String:
	return Profiles.day_key(int(Time.get_unix_time_from_system()), int(Time.get_time_zone_from_system().get("bias", 0)))


## Sekunden, die heute noch bleiben (-1 = ohne Grenze). running: die laufende Runde.
func kid_time_left(running := 0) -> int:
	if not is_kid():
		return -1
	return Profiles.time_left(kid_rules(), kid_time(), kid_today(), running)

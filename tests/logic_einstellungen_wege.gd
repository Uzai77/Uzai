extends Node
## Wege durch die Einstellungen ohne Bilder: Jeder Config-Schlüssel, der vor dem Umbau (0.12)
## über eine Zeile erreichbar war, ist es weiter (Liste VORHER unten); jede Unterseite, die von
## außen geöffnet wird (Downloads, Speicher, Remote Play, Nuvio, Erste Hilfe, Doktor), gibt es;
## höchstens zwei Ebenen; kurze Sätze; die Suche findet das Häufige. Mit UZAI_WEGE_DUMP=1 druckt
## der Test die ganze Struktur.
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_einstellungen_wege.tscn

const SettingsView := preload("res://src/ui/sections/settings_view.gd")
const Trouble := preload("res://src/core/trouble.gd")
const Search := preload("res://src/core/search.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


## Config-Schlüssel, die vor dem Umbau über Zeilen der Einstellungen erreichbar waren (Stand
## 0.11, Demo-Bibliothek, Standardwerte plus die Zustände aus ZUSTAENDE), dazu die fünf aus den
## früheren dritten Ebenen (Konten › Steam/Spotify/Discord › Mehr), die nicht einmal die Suche fand.
const VORHER: Array = ["accounts.discord_dm", "accounts.discord_presence", "accounts.discord_voice", "accounts.ra_key", "accounts.ra_toasts",
	"accounts.ra_user", "accounts.sgdb_key", "badges.real_logos", "capture.audio", "capture.battery", "capture.buffer", "capture.cap_gb",
	"capture.discord_mb", "capture.folder", "capture.fps", "capture.hotkey", "capture.length", "capture.mic", "capture.quality", "capture.source",
	"capture.via", "capture.videos", "controller.deadzone", "controller.glyphs", "controller.guide_combo", "controller.guide_hold",
	"controller.hide_mouse", "controller.repeat_delay", "controller.repeat_rate", "controller.rumble_events", "controller.rumble_friends",
	"controller.swap_ab", "controller.vibration", "display.light", "downloads.night", "downloads.night_from", "downloads.night_to",
	"downloads.night_updates", "library.amazon_enabled", "library.battlenet_enabled", "library.ea_enabled", "library.epic_enabled",
	"library.epic_owned", "library.epic_uzai", "library.folder_hide", "library.gog_enabled", "library.gog_galaxy", "library.install_auto",
	"library.itch_enabled", "library.libretro_images", "library.media_dir", "library.riot_enabled", "library.scan_on_start", "library.steam_dir",
	"library.steam_enabled", "library.steam_images", "library.steam_install_lib", "library.steam_owned", "library.ubisoft_enabled",
	"library.web_info", "library.xboxpc_enabled", "lossless.auto", "lossless.delay", "lossless.exe", "lossless.filter", "lossless.hotkey",
	"movies.autoplay_next", "movies.no_p2p", "movies.quality", "movies.tmdb_key", "music.browser", "music.local_dir", "notify.discord",
	"notify.in_game", "notify.steam", "notify.unlock_popups", "notify.unlock_pos", "notify.unlock_rare", "notify.unlock_sound",
	"notify.wish_sales", "rest.mute", "rest.pc_suspend", "rest.saver", "rest.saver_motion", "rest.saver_rest", "rest.saver_shots",
	"rest.screen_off", "room.kachel", "room.start", "shaderglass.enabled", "shaderglass.exe", "steam.status_nonsteam", "system.autostart",
	"system.background_wake", "system.backup_before_update", "system.clip_keys", "system.doktor_hint", "system.game_page", "system.language",
	"system.launch_card", "system.live_method", "system.live_tiles", "system.music_mode", "system.notifications", "system.on_start",
	"system.pause_on_guide", "system.perf_corner", "system.power_off", "system.round_summary", "system.search_online", "system.stream_keys",
	"theme.aurora", "theme.background", "theme.background_image", "theme.bg_soft", "theme.boot", "theme.clock_24h", "theme.corners",
	"theme.cover_shape", "theme.cover_size", "theme.dim", "theme.display", "theme.font", "theme.font_file", "theme.motes", "theme.music",
	"theme.music_track", "theme.preset", "theme.reduce_motion", "theme.sound_set", "theme.sound_space", "theme.system_intro", "theme.tabs",
	"theme.tint", "theme.ui_scale", "twitch.lang", "youtube.autoplay", "youtube.cookies", "youtube.cookies_file", "youtube.display",
	"youtube.hide_shorts", "youtube.mpv", "youtube.quality", "youtube.region", "youtube.shorts_tab", "youtube.sub_langs", "youtube.subtitles",
	"accounts.steam_key", "accounts.steam_id", "accounts.spotify_client_id", "accounts.discord_client_id", "accounts.discord_client_secret"]

## Zustände, in denen zusätzliche Zeilen erscheinen (eigenes Bild, eigene Schrift, Cookies-Datei,
## eigene Musikdateien (Standard), Aufnahme über die Game Bar, Spotify bzw. Musik-Apps als Musikquelle).
const ZUSTAENDE := [
	{},
	{ "theme.background": "bild", "theme.font": "datei", "youtube.cookies": "datei", "system.music_mode": "lokal", "capture.via": "gamebar" },
	{ "system.music_mode": "spotify" },
	{ "system.music_mode": "tasten" },
]

## Unterseiten, die andere Stellen öffnen (open_more, open_setting, Doktor, Erste Hilfe).
const VON_AUSSEN := [["spiele", "Installieren und Downloads"], ["spiele", "Weitere Launcher"], ["spiele", "Mehr"], ["aussehen", "Mehr"],
	["system", "Speicher"], ["system", "Leistung"], ["system", "Erste Hilfe"], ["imspiel", "Remote Play Together"], ["konten", "Nuvio"],
	["konten", "Steam"], ["konten", "Discord"], ["konten", "Spotify"], ["konten", "SteamGridDB"], ["medien", "Mehr zu Videos"]]

## Unterseiten, deren Sätze Daten sind (Lizenzen, Messwerte, Datenschutz): dort gilt keine Grenze.
const DATEN_SEITEN := ["Gespeichert und gesendet", "Leistung", "Über Uzai", "Filter-Profile", "Speicher", "Erste Hilfe"]


func _ready() -> void:
	await get_tree().process_frame
	Library.load_demo()
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	get_tree().root.add_child(host)
	var sv = SettingsView.new()
	sv.main = null
	host.add_child(sv)
	await get_tree().process_frame
	var dump := OS.get_environment("UZAI_WEGE_DUMP") != ""
	var rows: Array = []
	var seen := {}
	for st in ZUSTAENDE:
		for k in st.keys():
			Config.set_value(k, st[k])
		for r in sv.search_index():
			var id := "%s|%s|%s" % [r.cat, r.more, r.key]
			if not seen.has(id):
				seen[id] = true
				rows.append(r)
		for k in st.keys():
			Config.set_value(k, Config.DEFAULTS.get(k, null))
	if dump:
		_dump(sv, rows)
	else:
		_schluessel(rows)
		_struktur(sv, rows)
		_wege(sv, rows)
		_texte(rows)
		_suche(sv, rows)
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _dump(sv, rows: Array) -> void:
	var paths := {}
	for c in sv.CATS:
		var cid := str(c[0])
		print("== %s (%s)" % [c[1], cid])
		var mores := {}
		for r in rows:
			if str(r.cat) != cid:
				continue
			if str(r.more) == "":
				print("   %s  [%s] %s" % [r.title, r.path, ("– " + str(r.desc)) if str(r.desc) != "" else ""])
			else:
				if not mores.has(str(r.more)):
					mores[str(r.more)] = []
				(mores[str(r.more)] as Array).append(r)
		for m in mores.keys():
			print("   › %s" % m)
			for r in mores[m]:
				print("      %s  [%s] %s" % [r.title, r.path, ("– " + str(r.desc)) if str(r.desc) != "" else ""])
	for r in rows:
		if str(r.path) != "":
			paths[str(r.path)] = true
	var list: Array = paths.keys()
	list.sort()
	print("PFADE %d" % list.size())
	print("PFADLISTE " + JSON.stringify(list))


func _schluessel(rows: Array) -> void:
	print("Schlüssel")
	var paths := {}
	for r in rows:
		if str(r.path) != "":
			paths[str(r.path)] = true
	var fehlt: Array = []
	for p in VORHER:
		if not paths.has(str(p)):
			fehlt.append(p)
	check(fehlt.is_empty(), "alle %d Schlüssel von vorher weiter erreichbar%s" % [VORHER.size(), ("" if fehlt.is_empty() else ": fehlt " + str(fehlt))])
	check(paths.size() >= VORHER.size(), "%d Schlüssel über Zeilen erreichbar" % paths.size())
	var doppelt: Array = []
	var keys := {}
	for r in rows:
		var id := "%s|%s|%s" % [r.cat, r.more, r.key]
		if keys.has(id):
			doppelt.append(id)
		keys[id] = true
	check(doppelt.is_empty(), "jede Zeile hat einen eigenen Schlüssel%s" % ("" if doppelt.is_empty() else ": " + str(doppelt)))


func _struktur(sv, rows: Array) -> void:
	print("Struktur")
	var ids: Array = sv.CATS.map(func(c: Array) -> String: return str(c[0]))
	check(ids.size() == 11 and ids[0] == "aussehen" and ids[1] == "klang" and ids[ids.size() - 1] == "system",
			"elf Kategorien, Aussehen und Klang vorn, System zuletzt: %s" % str(ids))
	for a in [["bibliothek", "spiele"], ["emulatoren", "emulation"], ["systeme", "emulation"], ["bildfilter", "emulation"], ["videos", "medien"],
			["filme", "medien"], ["musik", "klang"], ["info", "system"], ["aufnahmen", "aufnahmen"], ["imspiel", "imspiel"]]:
		check(sv.resolve_sub(str(a[0])) == str(a[1]) and ids.has(str(a[1])), "alter Ort „%s“ führt nach %s" % [a[0], a[1]])
	# Höchstens zwei Ebenen: in keiner Unterseite liegt eine weitere („…“-Zeile mit more:-Schlüssel).
	var tief: Array = []
	for r in rows:
		if str(r.more) != "" and str(r.key).begins_with("more:"):
			tief.append("%s › %s › %s" % [r.cat, r.more, r.title])
	check(tief.is_empty(), "keine dritte Ebene%s" % ("" if tief.is_empty() else ": " + str(tief)))
	for cid in ids:
		var n := rows.filter(func(r: Dictionary) -> bool: return str(r.cat) == cid and str(r.more) == "").size()
		check(n >= 3 and n <= 20, "%s: %d Zeilen auf der Seite (3 bis 20)" % [cid, n])
	# Klang hat alles Hörbare; Mitteilungen keine Töne mehr; Spiele einen Einlese-Knopf, Emulation keinen.
	var klang := rows.filter(func(r: Dictionary) -> bool: return str(r.cat) == "klang").map(func(r: Dictionary) -> String: return str(r.path))
	for p in ["theme.sound_volume", "theme.sound_set", "theme.sound_space", "theme.music", "theme.music_track", "system.music_mode", "system.notifications",
			"notify.unlock_sound"]:
		check(klang.has(p), "Klang: %s" % p)
	check(rows.filter(func(r: Dictionary) -> bool: return str(r.key) == "emu:rescan").map(func(r: Dictionary) -> String: return str(r.cat)) == ["spiele"],
			"„Spiele neu einlesen“ genau einmal, unter Spiele")
	check(rows.filter(func(r: Dictionary) -> bool: return str(r.key) == "sgdb_all").map(func(r: Dictionary) -> String: return str(r.more)) == ["Bilder"],
			"„Cover holen“ genau einmal, unter Spiele › Bilder")


func _wege(sv, rows: Array) -> void:
	print("Wege von außen")
	for v in VON_AUSSEN:
		check(rows.any(func(r: Dictionary) -> bool: return str(r.cat) == str(v[0]) and str(r.more) == str(v[1])), "Unterseite %s › %s" % [v[0], v[1]])
	# Erste Hilfe (trouble.gd) und Doktor zeigen auf „seite:<Kategorie>[/Unterseite][#Zeile]“.
	var ziele: Array = ["seite:emulation", "seite:controller", "seite:aussehen"]
	for p in Trouble.FIRST_AID:
		for a in (p as Dictionary).actions:
			if str(a[1]).begins_with("seite:"):
				ziele.append(str(a[1]))
	ziele.append("seite:aussehen/Mehr#Leichter Modus")   # main.gd: Hinweis auf den Leichten Modus
	for z in ziele:
		var target := str(z).trim_prefix("seite:")
		var cat: String = sv.resolve_sub(target.get_slice("/", 0).get_slice("#", 0))
		var more := target.get_slice("/", 1).get_slice("#", 0) if target.contains("/") else ""
		var row := target.get_slice("#", 1) if target.contains("#") else ""
		var key := ("set:%s:%s%s" % [cat, (more + ":") if more != "" else "", row]) if row != "" else ""
		var ok: bool = sv.CATS.any(func(c: Array) -> bool: return str(c[0]) == cat)
		if more != "":
			ok = ok and rows.any(func(r: Dictionary) -> bool: return str(r.cat) == cat and str(r.more) == more)
		if key != "":
			ok = ok and rows.any(func(r: Dictionary) -> bool: return str(r.cat) == cat and str(r.more) == more and str(r.key) == key)
		check(ok, "Ziel „%s“ gibt es" % z)


func _texte(rows: Array) -> void:
	print("Texte")
	var lang: Array = []
	var saetze := 0
	var haupt := 0
	for r in rows:
		var d := str(r.desc)
		if str(r.more) == "":
			haupt += 1
			if d != "":
				saetze += 1
			if d.length() > 90:
				lang.append("%s: %s" % [r.title, d])
		elif d.length() > 160 and not DATEN_SEITEN.has(str(r.more)):
			lang.append("%s › %s: %s" % [r.more, r.title, d])
	check(lang.is_empty(), "kein Satz länger als 90 Zeichen auf Seiten, 160 in Unterseiten%s" % ("" if lang.is_empty() else ": " + str(lang)))
	check(saetze * 2 <= haupt, "höchstens jede zweite Zeile einer Seite trägt einen Satz (%d von %d)" % [saetze, haupt])
	var laut: Array = []
	for r in rows:
		var d := str(r.desc)
		for w in ["Alles freiwillig", "lädt selbst nichts", "ganz einfach", "einfach nur", "Keine Sorge", "problemlos", "kinderleicht"]:
			if d.contains(w):
				laut.append(r.title)
	check(laut.is_empty(), "keine Beruhigungs- oder Werbesätze%s" % ("" if laut.is_empty() else ": " + str(laut)))


func _suche(sv, rows: Array) -> void:
	print("Suche")
	# Den Index aus den schon gebauten Zeilen füllen (sonst baute die Suche alle Seiten noch einmal).
	sv._index_cache = Search.prepare(rows, func(s: Dictionary) -> String: return str(s.title) + " " + str(s.get("such", "")))
	var idx: Array = sv._suche_index()
	check(idx.size() > 250, "Index mit %d Zeilen" % idx.size())
	var erste := func(q: String) -> String:
		var t: Array = Search.rank(idx, q, 1)
		return str(t[0].title) if not t.is_empty() else ""
	check(erste.call("cover gr") == "Cover-Größe", "„cover gr“ → Cover-Größe")
	check(erste.call("lautst") == "Menüklänge", "„lautst“ → Menüklänge (Suchwort)")
	check(erste.call("speicherort") in ["Speicher", "Datenordner", "Speicherort neuer Steam-Spiele"], "„speicherort“ → Speicher (%s)" % erste.call("speicherort"))
	check(erste.call("emulatoren") != "", "„emulatoren“ findet etwas")
	check(Search.rank(idx, "qwxyz", 3).is_empty(), "Unsinn findet nichts")
	for h in sv.HAEUFIG:
		var e: Dictionary = sv._suche_eintrag(str(h[0]), str(h[1]), str(h[2]))
		check(not e.is_empty(), "Häufig: %s %s" % [h[0], h[1]])
	check(sv.HAEUFIG.size() <= 6, "höchstens sechs häufige Einträge")

extends RefCounted
## Mehrere Nutzerprofile (Roadmap 109) wie auf einer Konsole. Nur Daten und Rechnen – ohne
## Fenster testbar (tests/logic_profile.gd); Config hält das aktive Profil, die Oberfläche liegt in
## src/ui/layers/profile_*.gd.
##
## Aufbau im Datenordner:
##   profiles.json            die Profile (Name, Bild, Farbe, PIN-Hash, Kinderprofil), das zuletzt
##                            gewählte, das Profil des Altbestands und die Bremse für Fehlversuche
##   gemeinsam.json           Einstellungen, die für alle gelten (SHARED: Spieleordner, Emulatoren,
##                            Bildschirm, Downloads …)
##   library.json             die Bibliothek für alle – ohne die persönlichen Felder (PERSONAL)
##   profiles/<id>/           alles, was einem Profil gehört: settings.json (eigene Einstellungen,
##                            Theme, Anmeldungen im eigenen Tresor), spieler.json (Favoriten,
##                            Spielzeit, Backlog, Listen), Verlauf, Zimmer, Tresor-Schlüssel …
## Welche Dateien einem Profil gehören, steht in OWN_FILES und OWN_DIRS: Config.path() leitet sie
## von selbst in den Ordner des aktiven Profils – die Module merken davon nichts.
##
## Pfade entstehen nur aus Kennungen nach fester Regel (valid_id), nie aus Namen. Gelesen wird
## streng (Größe begrenzt, nur JSON, jeder Wert geprüft); geschrieben atomar (Config.write_json).
##
## PIN: nur als gesalzener, absichtlich langsamer Hash (PBKDF2-HMAC-SHA256). Nach Fehlversuchen
## wächst die Wartezeit. Ehrlich gesagt ist das Kinderschutz und Privatsphäre am Familien-PC –
## keine Sicherheitsgrenze gegen jemanden, der an das Windows-Konto kommt (die Daten liegen dort
## für jedes Programm dieses Kontos lesbar).

const FILE := "profiles.json"
const SHARED_FILE := "gemeinsam.json"
const DIR := "profiles"
const FORMAT := 1
const MAX_BYTES := 256 * 1024
const MAX_PROFILES := 8
const ID_LEN := 12
const ID_MIN := 8
const ID_MAX := 16
const NAME_MAX := 20
## Tresor-Schlüssel (src/core/vault.gd) – liegen je Profil in seinem Ordner.
const KEY_FILES := ["schluessel.dpapi", "schluessel.dpapi.alt", "schluessel.test"]

const PIN_MIN := 4
const PIN_MAX := 8
const PIN_ITER := 60000           ## gut eine Zehntelsekunde auf einem üblichen PC (im eigenen Faden)
const PIN_ITER_MIN := 1000
const PIN_ITER_MAX := 2000000
## Bremse: so viele Fehlversuche ohne Wartezeit, danach 30 s, 60 s, 120 s … höchstens 15 Minuten.
const BRAKE_FREE := 3
const BRAKE_BASE := 30
const BRAKE_MAX := 900

## Farben der Profile [Kennung, Name, Farbe] – gedämpft, auf dunklem und hellem Grund lesbar.
## Die erste ist der Standard neuer Profile: Lavendel wie der Akzent der Marke (docs/DESIGN.md).
## Vorhandene Profile behalten ihre Farbe (auch „gold“, den früheren Standard).
const COLORS := [
	["lavendel", "Lavendel", Color("#b8a6f0")], ["gold", "Gold", Color("#e2bd76")], ["koralle", "Koralle", Color("#e48a6c")],
	["rose", "Rosé", Color("#dd7f9c")], ["violett", "Violett", Color("#a48ae0")], ["blau", "Blau", Color("#6e9fe6")],
	["tuerkis", "Türkis", Color("#4fbcb8")], ["gruen", "Grün", Color("#7dc06e")], ["sand", "Sand", Color("#c8b089")],
	["schiefer", "Schiefer", Color("#8e9bb0")], ["rot", "Rot", Color("#de5f5a")],
]
## Profilbilder [Kennung, Name]: der Anfangsbuchstabe oder ein Zeichen aus Uzais Symbolsatz.
const AVATARS := [
	["buchstabe", "Anfangsbuchstabe"], ["games", "Controller"], ["star_f", "Stern"], ["heart_f", "Herz"],
	["music", "Musik"], ["moon", "Mond"], ["bolt", "Blitz"], ["spark", "Funke"], ["retro", "Retro"],
	["trophy", "Pokal"], ["disc", "Disc"], ["palette", "Farben"],
]
## Altersstufen eines Kinderprofils (USK-Stufen; PEGI wird darauf abgebildet).
const AGES := [[0, "Ab 0 Jahren"], [6, "Ab 6 Jahren"], [12, "Ab 12 Jahren"], [16, "Ab 16 Jahren"], [18, "Ab 18 Jahren"]]
## Spielzeit je Tag in Minuten (0 = ohne Grenze).
const LIMITS := [0, 30, 45, 60, 90, 120, 180, 240]
## So lange vor dem Ende kommt ein freundlicher Hinweis.
const LIMIT_WARN_S := 10 * 60

## Dateien und Ordner (relativ zum Datenordner), die einem Profil gehören.
const OWN_FILES := [
	"settings.json", "spieler.json", "sessions.json", "kind.json", "youtube.json", "movies.json",
	"nuvio.json", "unlocks.json", "badges.json", "epic_konto.json", "spotify_verlauf.json",
	# Zwischenspeicher, die aus den eigenen Konten stammen (Empfehlungen, Feeds, Weiterschauen)
	"cache/youtube-feed.json", "cache/youtube-recs.json", "cache/youtube-shorts.json",
	"cache/youtube-channels.json", "cache/youtube-tv-home.json", "cache/spotify_fuerdich.json",
	"cache/nuvio_home.json", "cache/musik/zuletzt.json", "cache/twitch.json",
	"cache/wunschliste-angebote.json", "cache/kacheln_erfolge.json", "cache/freunde_feed.json",
]
const OWN_DIRS := ["zimmer/"]
## Altbestand, der beim Umstellen nicht mitzieht, sondern wegfällt (Zwischenspeicher aus Konten).
const DROP_CACHES := ["cache/youtube-feed.json", "cache/youtube-recs.json", "cache/youtube-shorts.json",
	"cache/youtube-channels.json", "cache/youtube-tv-home.json", "cache/spotify_fuerdich.json",
	"cache/nuvio_home.json", "cache/wunschliste-angebote.json", "cache/kacheln_erfolge.json"]

## Einstellungen, die für alle Profile gelten (ganze Abschnitte oder einzelne Werte). Nie etwas
## aus dem Tresor (Vault.SECRETS) – Anmeldungen gehören immer einem Profil.
const SHARED := [
	"systems", "emulators", "filters", "shaderglass", "launcher", "lossless", "downloads", "display",
	"einrichtung", "capture", "remoteplay", "installs", "ton",
	"library.rom_dirs", "library.media_dir", "library.steam_enabled", "library.steam_dir", "library.steam_owned",
	"library.steam_images", "library.libretro_images", "library.web_info", "library.epic_enabled",
	"library.epic_owned", "library.steam_install_lib", "library.install_auto", "library.ea_enabled", "library.epic_uzai_dir",
	"library.gog_enabled", "library.gog_galaxy", "library.ubisoft_enabled", "library.battlenet_enabled", "library.xboxpc_enabled",
	"library.amazon_enabled", "library.itch_enabled", "library.riot_enabled",
	"library.pc_dirs", "library.scan_on_start",
	"youtube.mpv", "youtube.ytdlp", "music.local_dir",
	# Der Browser-Kern liegt einmal auf dem PC (helper/browser): Sein Stand gehört nicht einem Profil. Vorher hielt
	# ihn jedes weitere Profil für nicht eingerichtet und lud ihn neu.
	"browser.kern", "browser.kern_fassung", "browser.kern_abi", "browser.kern_gesund", "browser.kern_pruefung",
	"browser.kern_fehler", "browser.kern_generation", "browser.kern_naechste", "browser.kern_vorab", "browser.kern_grafik",
	# Was Uzai an Windows, Steam oder einem Emulator verstellt hat und zurückstellen muss – auch wenn nach einem
	# Absturz ein anderes Profil startet.
	"emu", "room.raumton_zurueck", "controller.steam_guide_aus", "controller.steam_guide_standard", "notify.steam_still",
	"system.autostart", "system.background_wake", "system.backup_before_update", "system.updates", "system.power_restore",
	"system.first_run", "system.power_off", "system.clip_keys", "system.stream_keys",
	"system.steam_overlay_keys", "system.live_method",
	# Persönliche Schlüssel, gelten aber für den ganzen PC (gemeinsamer Tresor, siehe Config): Die
	# Bibliothek und ihre Bilder teilen sich alle Profile.
	"accounts.sgdb_key", "accounts.iidb_key",
]
## Geheimes in SHARED: liegt im gemeinsamen Tresor (Config._shared_keys), nie offen. Anmeldungen
## gehören nie hierher – nur Schlüssel, die für den ganzen PC gelten.
const SHARED_SECRETS := ["accounts.sgdb_key", "accounts.iidb_key"]
## Felder eines Spiels, die jedem Profil selbst gehören (spieler.json); alles andere am Spiel
## (Titel, Bilder, Ordner, Emulator, eigene Angaben …) gilt für alle.
const PERSONAL := ["favorite", "last_played", "playtime", "plays", "status", "status_at", "done_at",
	"stars", "review", "diary", "presence_hidden", "notes"]
const PERSONAL_MAX_GAMES := 20000


# --- Kennungen und Namen ----------------------------------------------------------------------

## Nur a–z und 0–9, 8 bis 16 Zeichen. Daraus und nur daraus entstehen Ordnernamen.
static func valid_id(id: Variant) -> bool:
	if not (id is String):
		return false
	var s: String = id
	if s.length() < ID_MIN or s.length() > ID_MAX:
		return false
	for ch in s:
		if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")):
			return false
	return true


## Neue zufällige Kennung (gleichverteilt über a–z0–9).
static func new_id(taken: Array = []) -> String:
	const ABC := "abcdefghijklmnopqrstuvwxyz0123456789"
	var c := Crypto.new()
	while true:
		var out := ""
		while out.length() < ID_LEN:
			for b in c.generate_random_bytes(ID_LEN * 2):
				if b < 252 and out.length() < ID_LEN:
					out += ABC[b % 36]
		if not taken.has(out):
			return out
	return ""


## Name säubern: keine Steuer- und Richtungszeichen, Leerraum zusammengefasst, höchstens NAME_MAX.
static func clean_name(v: Variant) -> String:
	if not (v is String):
		return ""
	var out := ""
	var space := false
	for ch in (v as String):
		var u := ch.unicode_at(0)
		if u < 32 or u == 127 or (u >= 0x80 and u < 0xA0) or (u >= 0x200B and u <= 0x200F) or (u >= 0x202A and u <= 0x202E) \
				or (u >= 0x2066 and u <= 0x2069) or u == 0xFEFF:
			ch = " "
			u = 32
		if u == 32 or ch == " ":
			space = true
			continue
		if space and out != "":
			out += " "
		space = false
		out += ch
	return out.substr(0, NAME_MAX).strip_edges()


static func color_of(p: Dictionary) -> Color:
	var id := str(p.get("color", ""))
	for c in COLORS:
		if c[0] == id:
			return c[2]
	return COLORS[0][2]


static func _known(list: Array, v: Variant) -> bool:
	for e in list:
		if e[0] == v:
			return true
	return false


# --- Datei ------------------------------------------------------------------------------------

## Ein Profil aus der Datei prüfen. {} = unbrauchbar (fällt weg).
static func clean_profile(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	var id: Variant = d.get("id", "")
	var name := clean_name(d.get("name", ""))
	if not valid_id(id) or name == "":
		return {}
	var out := { "id": str(id), "name": name, "color": str(COLORS[0][0]), "avatar": "buchstabe", "created": 0, "kid": false }
	if _known(COLORS, d.get("color")):
		out.color = str(d.color)
	if _known(AVATARS, d.get("avatar")):
		out.avatar = str(d.avatar)
	if (d.get("created") is int or d.get("created") is float) and float(d.created) > 0.0 and float(d.created) < 1e11:
		out.created = int(d.created)
	var pin := clean_pin(d.get("pin"))
	if not pin.is_empty():
		out["pin"] = pin
	if d.get("kid") is bool and bool(d.kid):
		out.kid = true
	out["rules"] = clean_rules(d.get("rules"))
	return out


## PIN-Eintrag prüfen: { salt (16 Byte), hash (32 Byte), iter } oder {}.
static func clean_pin(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return {}
	var d: Dictionary = v
	var salt := _b64_bytes(d.get("salt"), 16)
	var hash := _b64_bytes(d.get("hash"), 32)
	var iter: Variant = d.get("iter")
	if salt.is_empty() or hash.is_empty() or not (iter is int or iter is float):
		return {}
	if float(iter) < PIN_ITER_MIN or float(iter) > PIN_ITER_MAX:
		return {}
	return { "salt": str(d.salt), "hash": str(d.hash), "iter": int(iter) }


static func _b64_bytes(v: Variant, n: int) -> PackedByteArray:
	if not (v is String) or (v as String).length() > 64:
		return PackedByteArray()
	var s: String = v
	if s.length() < 4 or s.length() % 4 != 0:
		return PackedByteArray()
	for ch in s:
		if not (ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="):
			return PackedByteArray()
	var raw := Marshalls.base64_to_raw(s)
	return raw if raw.size() == n else PackedByteArray()


## Regeln eines Kinderprofils (auch gespeichert, solange es kein Kinderprofil ist).
##   age      höchste Altersstufe (AGES)
##   unknown  Spiele ohne Altersangabe zeigen
##   shop / browser / chats  erlaubt (Standard: aus)
##   limit    Spielzeit je Tag in Minuten, 0 = ohne Grenze
static func clean_rules(v: Variant) -> Dictionary:
	var out := { "age": 12, "unknown": false, "shop": false, "browser": false, "chats": false, "limit": 0 }
	if not (v is Dictionary):
		return out
	var d: Dictionary = v
	if (d.get("age") is int or d.get("age") is float) and _known(AGES, int(d.age)):
		out.age = int(d.age)
	for k in ["unknown", "shop", "browser", "chats"]:
		if d.get(k) is bool:
			out[k] = bool(d[k])
	if (d.get("limit") is int or d.get("limit") is float) and LIMITS.has(int(d.limit)):
		out.limit = int(d.limit)
	return out


## Ganze Datei prüfen: { format, profiles, last, legacy, brake }.
static func clean_file(v: Variant) -> Dictionary:
	var out := { "format": FORMAT, "profiles": [], "last": "", "legacy": "", "brake": {} }
	if not (v is Dictionary):
		return out
	var d: Dictionary = v
	var seen := {}
	if d.get("profiles") is Array:
		for e in d.profiles:
			var p := clean_profile(e)
			if p.is_empty() or seen.has(p.id) or (out.profiles as Array).size() >= MAX_PROFILES:
				continue
			seen[p.id] = true
			out.profiles.append(p)
	for k in ["last", "legacy"]:
		if valid_id(d.get(k)) and seen.has(d[k]):
			out[k] = str(d[k])
	if d.get("brake") is Dictionary:
		for id in d.brake:
			if seen.has(id) and d.brake[id] is Dictionary:
				var b: Dictionary = d.brake[id]
				var fails := int(b.get("fails", 0)) if (b.get("fails") is int or b.get("fails") is float) else 0
				var until := int(b.get("until", 0)) if (b.get("until") is int or b.get("until") is float) else 0
				if fails > 0:
					out.brake[id] = { "fails": clampi(fails, 0, 1000), "until": maxi(until, 0) }
	return out


## profiles.json lesen (mit .bak/.tmp, wenn die Datei kaputt ist). Nie mehr als MAX_BYTES.
static func read_file(data_dir: String) -> Dictionary:
	var p := data_dir.path_join(FILE)
	for f in [p, p + ".bak", p + ".tmp"]:
		var v: Variant = read_small_json(f)
		if v is Dictionary:
			var c := clean_file(v)
			if not (c.profiles as Array).is_empty():
				return c
	return clean_file(null)


## Kleine JSON-Datei streng lesen: fehlt, zu groß oder kein JSON → null.
static func read_small_json(path: String, max_bytes := MAX_BYTES) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > max_bytes or f.get_length() == 0:
		return null
	var text := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(text) != OK:
		return null
	return j.data


static func write_file(data_dir: String, file: Dictionary) -> bool:
	return Config.write_json(data_dir.path_join(FILE), clean_file(file), "\t")


static func find(file: Dictionary, id: String) -> Dictionary:
	for p in file.get("profiles", []):
		if str(p.get("id", "")) == id:
			return p
	return {}


static func ids(file: Dictionary) -> Array:
	return (file.get("profiles", []) as Array).map(func(p: Dictionary) -> String: return str(p.id))


## Ordner eines Profils ("" bei ungültiger Kennung – nie ein Pfad aus etwas anderem).
static func dir_of(data_dir: String, id: String) -> String:
	if not valid_id(id):
		return ""
	return data_dir.path_join(DIR).path_join(id)


## Gehört diese Datei (relativ zum Datenordner) einem Profil?
static func is_own_path(rel: String) -> bool:
	if rel in OWN_FILES:
		return true
	for d in OWN_DIRS:
		if rel.begins_with(d) or rel + "/" == d:
			return true
	return false


## Neues Profil (ohne PIN). Name schon gesäubert und nicht leer.
static func make_profile(name: String, taken: Array, color := "", avatar := "buchstabe", now := -1) -> Dictionary:
	var c := color if _known(COLORS, color) else str(COLORS[taken.size() % COLORS.size()][0])
	return clean_profile({ "id": new_id(taken), "name": name, "color": c, "avatar": avatar,
		"created": int(Time.get_unix_time_from_system()) if now < 0 else now })


# --- PIN --------------------------------------------------------------------------------------

static func pin_format_ok(pin: String) -> bool:
	if pin.length() < PIN_MIN or pin.length() > PIN_MAX:
		return false
	for ch in pin:
		if not (ch >= "0" and ch <= "9"):
			return false
	return true


## PBKDF2-HMAC-SHA256, ein Block (32 Byte). Absichtlich langsam; im eigenen Faden aufrufen.
static func pbkdf2(password: PackedByteArray, salt: PackedByteArray, iter: int) -> PackedByteArray:
	var h := HMACContext.new()
	h.start(HashingContext.HASH_SHA256, password)
	h.update(salt + PackedByteArray([0, 0, 0, 1]))
	var u := h.finish()
	var a0 := u.decode_u64(0)
	var a1 := u.decode_u64(8)
	var a2 := u.decode_u64(16)
	var a3 := u.decode_u64(24)
	for i in maxi(iter, 1) - 1:
		h.start(HashingContext.HASH_SHA256, password)
		h.update(u)
		u = h.finish()
		a0 ^= u.decode_u64(0)
		a1 ^= u.decode_u64(8)
		a2 ^= u.decode_u64(16)
		a3 ^= u.decode_u64(24)
	var out := PackedByteArray()
	out.resize(32)
	out.encode_u64(0, a0)
	out.encode_u64(8, a1)
	out.encode_u64(16, a2)
	out.encode_u64(24, a3)
	return out


## Neue PIN als gesalzener Hash. {} bei ungültiger PIN.
static func make_pin(pin: String, iter := PIN_ITER) -> Dictionary:
	if not pin_format_ok(pin):
		return {}
	var salt := Crypto.new().generate_random_bytes(16)
	var hash := pbkdf2(pin.to_utf8_buffer(), salt, iter)
	return { "salt": Marshalls.raw_to_base64(salt), "hash": Marshalls.raw_to_base64(hash), "iter": iter }


## Stimmt die PIN zum gespeicherten Hash? (Vergleich in fester Zeit.)
static func check_pin(rec: Dictionary, pin: String) -> bool:
	var r := clean_pin(rec)
	if r.is_empty() or not pin_format_ok(pin):
		return false
	var got := pbkdf2(pin.to_utf8_buffer(), Marshalls.base64_to_raw(str(r.salt)), int(r.iter))
	return Crypto.new().constant_time_compare(got, Marshalls.base64_to_raw(str(r.hash)))


# --- Wer darf was ----------------------------------------------------------------------------

## Braucht eine Handlung eine PIN? actor: das aktive Profil, target: das betroffene ({} = ein
## neues). any_parent_pin: es gibt ein erwachsenes Profil mit PIN. Ergebnis: "" frei, "target" die
## PIN des Profils, "parent" eine Eltern-PIN, "no" gar nicht.
##   add     neues Profil – aus einem Kinderprofil nur mit Eltern-PIN
##   edit    Name, Bild, Farbe, PIN – fremde Profile mit PIN nur mit deren PIN (Eltern dürfen
##           Kinderprofile so ändern)
##   rules   Kinderprofil an/aus und seine Regeln – aus einem Kinderprofil nur mit Eltern-PIN
##   delete  nie das aktive; aus einem Kinderprofil nur mit Eltern-PIN; sonst mit der PIN des
##           Profils, wenn es eine hat (Kinderprofile dürfen Eltern ohne löschen)
static func guard(action: String, actor: Dictionary, target: Dictionary, any_parent_pin: bool) -> String:
	var actor_kid := bool(actor.get("kid", false))
	var same := not target.is_empty() and str(target.get("id", "")) == str(actor.get("id", ""))
	var t_pin := target.has("pin")
	var t_kid := bool(target.get("kid", false))
	match action:
		"add":
			return "parent" if actor_kid and any_parent_pin else ""
		"edit":
			if same or not t_pin or (t_kid and not actor_kid):
				return ""
			return "target"
		"rules":
			if actor_kid:
				return "parent" if any_parent_pin else ""
			return "target" if t_pin and not same and not t_kid else ""
		"delete":
			if same or target.is_empty():
				return "no"
			if actor_kid:
				return "parent" if any_parent_pin else ("target" if t_pin else "")
			return "target" if t_pin and not t_kid else ""
	return "no"


# --- Bremse -----------------------------------------------------------------------------------

## Sekunden, die noch zu warten sind (0 = darf versuchen). Eine vorgestellte Uhr verlängert nie
## über BRAKE_MAX hinaus.
static func brake_wait(b: Dictionary, now: int) -> int:
	var until := int(b.get("until", 0))
	if until <= now:
		return 0
	return mini(until - now, BRAKE_MAX)


## Nach einem Fehlversuch: neuer Stand der Bremse.
static func brake_fail(b: Dictionary, now: int) -> Dictionary:
	var fails := int(b.get("fails", 0)) + 1
	var out := { "fails": fails, "until": 0 }
	if fails >= BRAKE_FREE:
		var k := mini(fails - BRAKE_FREE, 10)
		out.until = now + mini(BRAKE_BASE * (1 << k), BRAKE_MAX)
	return out


## Versuche, die noch ohne Wartezeit bleiben (für den Hinweis).
static func brake_left(b: Dictionary) -> int:
	return maxi(0, BRAKE_FREE - int(b.get("fails", 0)))


# --- Kinderprofil -----------------------------------------------------------------------------

## Altersstufe eines Spiels aus den vorhandenen Angaben (Spieloptionen → Eigene Angaben: USK/PEGI).
## -1 = unbekannt.
static func game_age(g: Dictionary) -> int:
	var a := str(g.get("age", ""))
	var n := -1
	if a.begins_with("usk") and a.substr(3).is_valid_int():
		n = int(a.substr(3))
	elif a.begins_with("pegi") and a.substr(4).is_valid_int():
		# PEGI 3/7 liegen unter USK 6/12: auf die nächste USK-Stufe darüber.
		n = { 3: 6, 7: 12, 12: 12, 16: 16, 18: 18 }.get(int(a.substr(4)), -1)
	return n if n >= 0 and n <= 18 else -1


## Darf ein Kinderprofil dieses Spiel sehen und starten?
static func age_allowed(rules: Dictionary, g: Dictionary) -> bool:
	var a := game_age(g)
	if a < 0:
		return bool(rules.get("unknown", false))
	return a <= int(rules.get("age", 12))


## Tag nach Ortszeit („2026-10-23“): die Spielzeit zählt je Kalendertag.
static func day_key(unix: int, bias_min := 0) -> String:
	return Time.get_date_string_from_unix_time(unix + bias_min * 60)


static func clean_time(v: Variant) -> Dictionary:
	if not (v is Dictionary):
		return { "day": "", "secs": 0 }
	var d: Dictionary = v
	var day := str(d.get("day", ""))
	if day.length() != 10 or day.count("-") != 2:
		day = ""
	var secs := int(d.get("secs", 0)) if (d.get("secs") is int or d.get("secs") is float) else 0
	return { "day": day, "secs": clampi(secs, 0, 86400) }


## Heute schon gespielt (Sekunden).
static func time_used(state: Dictionary, day: String) -> int:
	return int(state.get("secs", 0)) if str(state.get("day", "")) == day else 0


## Spielzeit dazuzählen (ein neuer Tag fängt bei 0 an).
static func time_add(state: Dictionary, day: String, secs: int) -> Dictionary:
	return { "day": day, "secs": clampi(time_used(state, day) + maxi(secs, 0), 0, 86400) }


## Was heute noch bleibt (Sekunden); -1 = ohne Grenze. running: die laufende Runde.
static func time_left(rules: Dictionary, state: Dictionary, day: String, running := 0) -> int:
	var lim := int(rules.get("limit", 0))
	if lim <= 0:
		return -1
	return maxi(0, lim * 60 - time_used(state, day) - maxi(running, 0))


# --- Einstellungen: gemeinsam und eigen ---------------------------------------------------------

## Alle Einstellungen in [gemeinsam, eigen] teilen. Beide tragen Aufbau und Version.
static func split_settings(all: Dictionary) -> Array:
	var own := all.duplicate(true)
	var shared := {}
	for p in SHARED:
		var v: Variant = _take(own, p)
		if v != null:
			_put(shared, p, v)
	for k in ["schema", "uzai_version"]:
		if all.has(k):
			shared[k] = all[k]
	return [shared, own]


## Eigene Einstellungen und gemeinsame zusammenführen: die gemeinsamen gelten.
static func merge_settings(own: Dictionary, shared: Dictionary) -> Dictionary:
	var out := own.duplicate(true)
	for p in SHARED:
		var v: Variant = _peek(shared, p)
		if v != null:
			_put(out, p, v.duplicate(true) if (v is Dictionary or v is Array) else v)
	return out


static func _peek(d: Dictionary, key_path: String) -> Variant:
	var node: Variant = d
	for part in key_path.split("."):
		if not (node is Dictionary and (node as Dictionary).has(part)):
			return null
		node = node[part]
	return node


static func _take(d: Dictionary, key_path: String) -> Variant:
	var parts := key_path.split(".")
	var node: Variant = d
	for i in parts.size() - 1:
		if not (node is Dictionary and (node as Dictionary).get(parts[i]) is Dictionary):
			return null
		node = node[parts[i]]
	var last := parts[parts.size() - 1]
	if not (node as Dictionary).has(last):
		return null
	var v: Variant = node[last]
	(node as Dictionary).erase(last)
	return v


static func _put(d: Dictionary, key_path: String, v: Variant) -> void:
	var parts := key_path.split(".")
	var node: Dictionary = d
	for i in parts.size() - 1:
		if not (node.get(parts[i]) is Dictionary):
			node[parts[i]] = {}
		node = node[parts[i]]
	node[parts[parts.size() - 1]] = v


# --- Bibliothek: persönliche Felder ------------------------------------------------------------

## Persönliche Felder aller Spiele: { Spiel-ID: { Feld: Wert } } (nur Spiele mit etwas darin).
static func personal_of(games: Array) -> Dictionary:
	var out := {}
	for g in games:
		if not (g is Dictionary):
			continue
		var mine := {}
		for k in PERSONAL:
			if (g as Dictionary).has(k):
				mine[k] = g[k]
		if not mine.is_empty():
			out[str(g.get("id", ""))] = mine
	return out


## Spiele ohne persönliche Felder (Kopien, für library.json).
static func strip_games(games: Array) -> Array:
	var out: Array = []
	for g in games:
		if not (g is Dictionary):
			continue
		var c: Dictionary = (g as Dictionary).duplicate()
		for k in PERSONAL:
			c.erase(k)
		out.append(c)
	return out


## Persönliche Felder eines Profils an die Spiele setzen (alte vorher weg). per kommt aus
## clean_personal; was danach noch geprüft wird (Backlog, Zahlen), macht die Bibliothek.
static func apply_personal(games: Array, per: Dictionary) -> void:
	var map: Dictionary = per.get("games", {})
	for g in games:
		if not (g is Dictionary):
			continue
		for k in PERSONAL:
			(g as Dictionary).erase(k)
		var mine: Variant = map.get(str(g.get("id", "")))
		if mine is Dictionary:
			for k in mine:
				g[k] = mine[k]


## spieler.json streng prüfen: nur bekannte Felder mit passenden Typen. { games, lists, goals }
static func clean_personal(v: Variant) -> Dictionary:
	var out := { "games": {}, "lists": [], "goals": {} }
	if not (v is Dictionary):
		return out
	var d: Dictionary = v
	if d.get("games") is Dictionary:
		var n := 0
		for id in d.games:
			if n >= PERSONAL_MAX_GAMES:
				break
			if not (id is String) or (id as String).length() > 300 or not (d.games[id] is Dictionary):
				continue
			var mine := {}
			for k in PERSONAL:
				var val: Variant = (d.games[id] as Dictionary).get(k)
				if val == null:
					continue
				var ok := false
				match k:
					"favorite", "presence_hidden":
						ok = val is bool
					"last_played", "playtime", "plays", "status_at", "done_at", "stars":
						ok = (val is int or val is float) and float(val) >= 0.0 and float(val) < 1e12
					"status", "review", "notes":
						ok = val is String and (val as String).length() <= 4000
					"diary":
						ok = val is Array
				if ok:
					mine[k] = val
			if not mine.is_empty():
				out.games[id] = mine
				n += 1
	if d.get("lists") is Array:
		out.lists = d.lists
	if d.get("goals") is Dictionary:
		out.goals = d.goals
	return out


# --- Löschen ----------------------------------------------------------------------------------

## Ordner eines Profils löschen – nur in profiles/<id>, nie über Verknüpfungen (sie bleiben
## liegen, ihr Ziel wird nie angefasst). { ok, left } – left: was nicht gelöscht werden konnte.
static func delete_dir(data_dir: String, id: String) -> Dictionary:
	var dir := dir_of(data_dir, id)
	if dir == "":
		return { "ok": false, "left": 0 }
	var root := DirAccess.open(data_dir)
	if root == null or root.is_link(DIR):
		return { "ok": false, "left": 1 }
	var base := DirAccess.open(data_dir.path_join(DIR))
	if base == null or base.is_link(id):
		return { "ok": false, "left": 1 }
	if not DirAccess.dir_exists_absolute(dir):
		return { "ok": true, "left": 0 }
	var left := _wipe(dir, 0)
	if left == 0:
		DirAccess.remove_absolute(dir)
	else:
		# Reste (Verknüpfungen) beiseitelegen: der Name ist keine gültige Kennung mehr, so taucht
		# das Profil nie wieder auf. Umbenennen folgt keiner Verknüpfung.
		base.rename(id, "geloescht-%s-%d" % [id, Time.get_ticks_usec()])
	return { "ok": left == 0 and not DirAccess.dir_exists_absolute(dir), "left": left }


static func _wipe(dir: String, depth: int) -> int:
	if depth > 12:
		return 1
	var da := DirAccess.open(dir)
	if da == null:
		return 1
	da.include_hidden = true
	var left := 0
	for f in da.get_files():
		if da.is_link(f):
			left += 1
			continue
		if DirAccess.remove_absolute(dir.path_join(f)) != OK:
			left += 1
	for sub in da.get_directories():
		if da.is_link(sub):
			left += 1
			continue
		var n := _wipe(dir.path_join(sub), depth + 1)
		if n == 0:
			DirAccess.remove_absolute(dir.path_join(sub))
		left += n
	return left

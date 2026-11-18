extends RefCounted
## Tresor für Anmeldungen (Punkt 71). Erneuerungs-Anmeldungen, Zugänge und Schlüssel stehen in
## settings.json nur verschlüsselt („tresor1:…“) – auch in jeder Sicherung. Der Schlüssel dazu
## (32 Byte, zufällig) liegt in schluessel.dpapi, geschützt mit Windows DPAPI für dieses
## Windows-Konto: Wer settings.json oder eine Sicherung kopiert, kann damit auf einem anderen PC
## oder Konto nichts anfangen. Verfahren: AES-256-CBC mit zufälligem IV, danach HMAC-SHA256 über
## IV und Geheimtext (verschlüsseln, dann prüfen); beide Schlüssel aus dem Hauptschlüssel abgeleitet.
##
## DPAPI gibt es nur über Windows selbst: eine kurze PowerShell beim Start, in einem eigenen Faden
## (Config). Liegt Uzai portabel auf einem Stick und kommt an einen anderen PC, bleibt der alte
## Schlüssel als schluessel.dpapi.alt daneben – zurück am ersten PC geht wieder alles.
## Ohne Windows (nur Tests) liegt der Schlüssel offen in schluessel.test.

const PREFIX := "tresor1:"
const KEY_FILE := "schluessel.dpapi"
const ALT_FILE := "schluessel.dpapi.alt"
const TEST_FILE := "schluessel.test"
const ENTROPY := "Uzai-Tresor-1"
const Helper := preload("res://src/core/helper.gd")

## Was nur verschlüsselt gespeichert wird (Pfade in den Einstellungen). Addons stehen ganz drin:
## Ihre Adressen tragen oft Zugangsschlüssel.
const SECRETS := [
	"accounts.steam_key", "accounts.ra_key", "accounts.sgdb_key", "accounts.iidb_key", "accounts.ss_pass", "accounts.ss_devpass",
	"accounts.spotify_refresh", "accounts.spotify_app_refresh",
	"accounts.discord_client_secret", "accounts.discord_token", "accounts.discord_refresh",
	"accounts.discord_dm_token", "accounts.discord_dm_refresh",
	"accounts.epic_refresh", "accounts.youtube_tv_refresh",
	"accounts.twitch_refresh", "accounts.twitch_access",
	"accounts.steam_chat_refresh", "accounts.steam_chat_access",
	"youtube.client_secret", "youtube.refresh",
	"nuvio.refresh", "nuvio.access", "nuvio.addon_urls",
	"movies.tmdb_key", "movies.addons",
	"plex.token", "plex.server_token", "jellyfin.token", "emby.token", "stremio.auth",
]

const _CREATE := """Add-Type -AssemblyName System.Security
$k = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($k)
$e = [Text.Encoding]::UTF8.GetBytes('%s')
$b = [Security.Cryptography.ProtectedData]::Protect($k, $e, 'CurrentUser')
[Convert]::ToBase64String($b) + ' ' + [Convert]::ToBase64String($k)"""
const _OPEN := """Add-Type -AssemblyName System.Security
$e = [Text.Encoding]::UTF8.GetBytes('%s')
foreach ($s in @(%s)) { try { [Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($s), $e, 'CurrentUser')) } catch { '-' } }"""


# --- Verschlüsseln ----------------------------------------------------------------------------

## Wert (Text, Liste …) versiegeln. Leerer Text bleibt leer (nichts zu schützen).
static func seal(value: Variant, key: PackedByteArray) -> String:
	if value is String and value == "":
		return ""
	var c := Crypto.new()
	var iv := c.generate_random_bytes(16)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, _derive(key, "enc"), iv)
	var body := iv + aes.update(_pad(JSON.stringify(value).to_utf8_buffer()))
	aes.finish()
	return PREFIX + Marshalls.raw_to_base64(body + c.hmac_digest(HashingContext.HASH_SHA256, _derive(key, "mac"), body))


## Versiegelten Wert öffnen; versucht jeden Schlüssel. null = mit keinem zu öffnen (anderer PC,
## verändert). Nicht Versiegeltes kommt unverändert zurück (alte Einstellungen).
static func open(text: Variant, keys: Array) -> Variant:
	if not (text is String and (text as String).begins_with(PREFIX)):
		return text
	var b64 := (text as String).substr(PREFIX.length())
	if not _b64_ok(b64):
		return null
	var raw := Marshalls.base64_to_raw(b64)
	if raw.size() < 64 or (raw.size() - 48) % 16 != 0:
		return null
	var body := raw.slice(0, raw.size() - 32)
	var tag := raw.slice(raw.size() - 32)
	var c := Crypto.new()
	for k in keys:
		var key: PackedByteArray = k
		if key.size() != 32 or not c.constant_time_compare(c.hmac_digest(HashingContext.HASH_SHA256, _derive(key, "mac"), body), tag):
			continue
		var aes := AESContext.new()
		aes.start(AESContext.MODE_CBC_DECRYPT, _derive(key, "enc"), body.slice(0, 16))
		var plain := _unpad(aes.update(body.slice(16)))
		aes.finish()
		if plain.is_empty():
			return null
		var j := JSON.new()
		return j.data if j.parse(plain.get_string_from_utf8()) == OK else null
	return null


static func is_sealed(v: Variant) -> bool:
	return v is String and (v as String).begins_with(PREFIX)


static func _derive(key: PackedByteArray, label: String) -> PackedByteArray:
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key, ("Uzai/" + label).to_utf8_buffer())


static func _pad(b: PackedByteArray) -> PackedByteArray:
	var n := 16 - b.size() % 16
	var out := b.duplicate()
	for i in n:
		out.append(n)
	return out


static func _unpad(b: PackedByteArray) -> PackedByteArray:
	if b.is_empty():
		return PackedByteArray()
	var n := b[b.size() - 1]
	if n < 1 or n > 16 or n > b.size():
		return PackedByteArray()
	for i in n:
		if b[b.size() - 1 - i] != n:
			return PackedByteArray()
	return b.slice(0, b.size() - n)


# --- Schlüssel --------------------------------------------------------------------------------

## Schlüssel holen oder anlegen (im eigenen Faden, Config). { keys: [aktuell, alt …], how, error }
## how: "dpapi" (geschützt), "test" (ohne Windows), "" (ging nicht – Werte bleiben unverändert).
static func load_keys(data_dir: String) -> Dictionary:
	if not (OS.get_name() == "Windows"):
		return _test_key(data_dir)
	var cur := data_dir.path_join(KEY_FILE)
	var alt := data_dir.path_join(ALT_FILE)
	var blobs: Array = []
	for f in [cur, alt]:
		var b := FileAccess.get_file_as_string(f).strip_edges() if FileAccess.file_exists(f) else ""
		blobs.append(b if _b64_ok(b) else "")
	var opened: Array = ["", ""]
	if blobs.any(func(b: String) -> bool: return b != ""):
		var list := ", ".join(blobs.map(func(b: String) -> String: return "'%s'" % (b if b != "" else "-")))
		var lines := _ps(_OPEN % [ENTROPY, list])
		for i in mini(2, lines.size()):
			opened[i] = lines[i] if _b64_ok(lines[i]) else ""
	var keys: Array = []
	if opened[0] != "":
		keys.append(Marshalls.base64_to_raw(opened[0]))
		if opened[1] != "":
			keys.append(Marshalls.base64_to_raw(opened[1]))
		return { "keys": keys, "how": "dpapi", "error": "" }
	if opened[1] != "":
		# Zurück am PC des alten Schlüssels: tauschen.
		DirAccess.rename_absolute(cur, cur + ".tausch")
		DirAccess.rename_absolute(alt, cur)
		DirAccess.rename_absolute(cur + ".tausch", alt)
		return { "keys": [Marshalls.base64_to_raw(opened[1])], "how": "dpapi", "error": "" }
	# Neuer Schlüssel (erster Start, oder der vorhandene gehört zu einem anderen PC/Konto).
	var made := _ps(_CREATE % ENTROPY)
	var parts := (made[made.size() - 1] if not made.is_empty() else "").split(" ")
	if parts.size() != 2 or not _b64_ok(parts[0]) or not _b64_ok(parts[1]):
		return { "keys": [], "how": "", "error": "Windows-Schutz (DPAPI) nicht erreichbar" }
	if blobs[0] != "":
		DirAccess.remove_absolute(alt)
		DirAccess.rename_absolute(cur, alt)
	var f := FileAccess.open(cur, FileAccess.WRITE)
	if f == null:
		return { "keys": [], "how": "", "error": "Schlüsseldatei ließ sich nicht schreiben" }
	f.store_string(parts[0])
	f.close()
	return { "keys": [Marshalls.base64_to_raw(parts[1])], "how": "dpapi", "error": "" }


static func _test_key(data_dir: String) -> Dictionary:
	var p := data_dir.path_join(TEST_FILE)
	var b := FileAccess.get_file_as_string(p).strip_edges() if FileAccess.file_exists(p) else ""
	if not _b64_ok(b) or Marshalls.base64_to_raw(b).size() != 32:
		b = Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(32))
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f == null:
			return { "keys": [], "how": "", "error": "Schlüsseldatei ließ sich nicht schreiben" }
		f.store_string(b)
		f.close()
	return { "keys": [Marshalls.base64_to_raw(b)], "how": "test", "error": "" }


## Nur Base64-Zeichen: so kommt nie etwas anderes in das PowerShell-Skript.
static func _b64_ok(s: String) -> bool:
	if s.length() < 16 or s.length() > 1048576 or s.length() % 4 != 0:
		return false
	for ch in s:
		if not (ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="):
			return false
	return true


## Kurzes PowerShell-Skript (als -EncodedCommand, ohne Anführungszeichen-Fallen); Ausgabezeilen.
static func _ps(script: String) -> PackedStringArray:
	var out: Array = []
	var args := PackedStringArray(
			["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", Marshalls.raw_to_base64(script.to_utf16_buffer())])
	if OS.execute(Helper.ps_exe(), args, out, false) != 0 or out.is_empty():
		return PackedStringArray()
	var lines := PackedStringArray()
	for l in str(out[0]).split("\n"):
		if l.strip_edges() != "":
			lines.append(l.strip_edges())
	return lines

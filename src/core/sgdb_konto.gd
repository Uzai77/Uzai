extends RefCounted
## SteamGridDB-Schlüssel (persönlich, nie mitgeliefert): gilt für den ganzen PC – alle Profile
## teilen ihn (Profiles.SHARED, im gemeinsamen Tresor, siehe Config). Hier: Form prüfen und eine
## leichte Testabfrage bei SteamGridDB, bevor Uzai ihn speichert.

const API := "https://www.steamgriddb.com/api/v2"
const KEY_PAGE := "https://www.steamgriddb.com/profile/preferences/api"
const KEY_PATH := "accounts.sgdb_key"


## Form: SteamGridDB gibt 32 Zeichen aus Ziffern und a–f aus. "" = passt.
static func format_error(key: String) -> String:
	var k := key.strip_edges()
	if k == "":
		return "Kein Schlüssel angekommen. Auf steamgriddb.com unter API kopieren und nochmal senden."
	if k.length() != 32:
		return "Das sieht nicht wie ein SteamGridDB-Schlüssel aus (32 Zeichen). Auf steamgriddb.com unter API ganz kopieren und nochmal senden."
	for ch in k.to_lower():
		if not ch in "0123456789abcdef":
			return "Im Schlüssel steht ein fremdes Zeichen. Auf steamgriddb.com unter API ganz kopieren und nochmal senden."
	return ""


## Antwort der Testabfrage als Satz ("" = Schlüssel gilt).
static func answer_error(code: int) -> String:
	if code >= 200 and code < 300:
		return ""
	if code in [401, 403]:
		return "SteamGridDB kennt diesen Schlüssel nicht. Auf steamgriddb.com unter API einen neuen erzeugen und nochmal senden."
	if code == 0:
		return "SteamGridDB ist gerade nicht erreichbar. Ist der PC online? Gleich nochmal versuchen."
	return "SteamGridDB hat gerade nicht geantwortet. Gleich nochmal versuchen."


## Schlüssel prüfen (eine kleine Suche) und nur dann speichern. { ok, error }.
static func check_and_store(key: String) -> Dictionary:
	var k := key.strip_edges()
	var fe := format_error(k)
	if fe != "":
		return { "ok": false, "error": fe }
	var r: Dictionary = await Net.get_json(API + "/search/autocomplete/portal", PackedStringArray(["Authorization: Bearer " + k]))
	var ae := answer_error(int(r.get("code", 0)))
	if ae != "":
		return { "ok": false, "error": ae }
	Config.set_value(KEY_PATH, k)
	Config.save_settings()
	return { "ok": true, "error": "" }


static func connected() -> bool:
	return str(Config.get_value(KEY_PATH, "")) != ""

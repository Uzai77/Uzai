extends Node
## Tresor für Anmeldungen (Punkt 71): Versiegeln und Öffnen, nichts Verändertes oder Fremdes geht
## durch, settings.json enthält keine offenen Anmeldungen, alte offene Werte werden versiegelt.
## Aufruf: godot --headless --path . res://tests/logic_tresor.tscn

const Vault := preload("res://src/core/vault.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_crypto()
	_keys()
	await _config()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _crypto() -> void:
	print("Versiegeln")
	var c := Crypto.new()
	var k1 := c.generate_random_bytes(32)
	var k2 := c.generate_random_bytes(32)
	var s := Vault.seal("AQAAANCMnd8BFdERjHoAwE/Cl+sBAAAA-geheim-äöü", k1)
	check(s.begins_with(Vault.PREFIX) and not s.contains("geheim"), "versiegelt, Klartext nicht lesbar")
	check(str(Vault.open(s, [k1])) == "AQAAANCMnd8BFdERjHoAwE/Cl+sBAAAA-geheim-äöü", "öffnen mit dem richtigen Schlüssel")
	check(Vault.seal("x", k1) != Vault.seal("x", k1), "jedes Mal anders (zufälliger IV)")
	check(Vault.open(s, [k2]) == null, "falscher Schlüssel: nichts")
	check(str(Vault.open(s, [k2, k1])) != "", "zweiter Schlüssel (portabel an anderem PC) geht auch")
	var raw := Marshalls.base64_to_raw(s.substr(Vault.PREFIX.length()))
	raw[20] = raw[20] ^ 1
	check(Vault.open(Vault.PREFIX + Marshalls.raw_to_base64(raw), [k1]) == null, "veränderter Geheimtext: nichts")
	raw[20] = raw[20] ^ 1
	raw[raw.size() - 1] = raw[raw.size() - 1] ^ 1
	check(Vault.open(Vault.PREFIX + Marshalls.raw_to_base64(raw), [k1]) == null, "veränderte Prüfsumme: nichts")
	check(Vault.open(Vault.PREFIX + "AAAA", [k1]) == null and Vault.open(Vault.PREFIX + "%%%", [k1]) == null, "abgeschnitten oder Unsinn: nichts")
	check(str(Vault.open("offen", [k1])) == "offen", "nicht Versiegeltes kommt unverändert (alte Einstellungen)")
	check(Vault.seal("", k1) == "", "leer bleibt leer")
	var addons := [{ "url": "https://x.example/abc123/manifest.json", "name": "A" }, { "url": "https://y.example/manifest.json" }]
	var sa := Vault.seal(addons, k1)
	var back: Variant = Vault.open(sa, [k1])
	check(back is Array and (back as Array).size() == 2 and str(back[0].url) == str(addons[0].url), "Listen (Addons) gehen auch")


func _keys() -> void:
	print("Schlüssel")
	var d := Config.data_dir.path_join("test_tresor")
	DirAccess.make_dir_recursive_absolute(d)
	var a := Vault.load_keys(d)
	var b := Vault.load_keys(d)
	check(str(a.how) == "test" and (a.keys as Array).size() == 1 and (a.keys[0] as PackedByteArray).size() == 32, "ohne Windows: Testschlüssel angelegt")
	check(a.keys[0] == b.keys[0], "beim nächsten Start derselbe Schlüssel")
	check(not Vault._b64_ok("abc'); Remove-Item C:\\ -Recurse; ('") and not Vault._b64_ok("") and Vault._b64_ok("QUJDREVGR0hJSktMTU5PUA=="),
			"nur Base64 kommt ins PowerShell-Skript")
	check(Vault.Helper.ps_exe().ends_with("powershell.exe"), "PowerShell mit festem Namen")


func _config() -> void:
	print("Einstellungen")
	Config.set_value("accounts.spotify_refresh", "AQB-sehr-geheim-123")
	Config.set_value("movies.addons", [{ "url": "https://debrid.example/KEY999/manifest.json" }])
	Config.set_value("accounts.steam_id", "76561198000000001")
	Config.save_settings()
	await get_tree().create_timer(0.2).timeout
	var text := FileAccess.get_file_as_string(Config.path("settings.json"))
	check(not text.contains("AQB-sehr-geheim-123") and not text.contains("KEY999"), "settings.json ohne offene Anmeldungen")
	check(text.contains(Vault.PREFIX) and text.contains("76561198000000001"), "Geheimes versiegelt, Gewöhnliches lesbar")
	check(str(Config.get_value("accounts.spotify_refresh", "")) == "AQB-sehr-geheim-123", "Uzai liest den Wert wie bisher")
	# Wie nach einem Neustart: versiegelt laden, beim ersten Gebrauch öffnen.
	var saved: Variant = JSON.parse_string(text)
	Config.settings = Config.deep_merge(Config.DEFAULTS, saved)
	Config.sanitize(Config.settings, Config.DEFAULTS)
	check(Vault.is_sealed(Config.settings.movies.addons), "versiegelte Liste übersteht die Typprüfung")
	var ad: Variant = Config.get_value("movies.addons", [])
	check(ad is Array and str(ad[0].url).contains("KEY999"), "Liste nach dem Laden wieder da")
	check(str(Config.get_value("accounts.spotify_refresh", "")) == "AQB-sehr-geheim-123", "Anmeldung nach dem Laden wieder da")
	# Fremd versiegelt (anderer PC): leer statt Unsinn, und der Wert bleibt für den richtigen PC.
	var foreign := Vault.seal("anderer-pc", Crypto.new().generate_random_bytes(32))
	Config.settings.accounts["epic_refresh"] = foreign
	check(str(Config.get_value("accounts.epic_refresh", "")) == "", "fremd versiegelt: wie abgemeldet")
	Config.save_settings()
	await get_tree().create_timer(0.2).timeout
	check(FileAccess.get_file_as_string(Config.path("settings.json")).contains(foreign), "fremd Versiegeltes bleibt in der Datei")

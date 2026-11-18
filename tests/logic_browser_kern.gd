extends Node
## Browser-Kern (src/core/browser_kern.gd), alles ohne Windows: Fassungen vergleichen, Rückrufe, Wahl des Baus aus
## der Liste (fremde Daten), Meilenstein, Installer-Zeile, Prüfsummen-Beilage, Update-Takt, Stummel (Prüfsumme in
## Uzai, Helfer und Datei; nur Export RunWinMain), Konfiguration des Kerns in Uzai und Helfer gleich, der Kern-Quelltext
## (API-Fassung, Hash, feste Sicherheits-Einstellungen), die Leitung (neue Befehle/Ereignisse).
## Aufruf: godot --headless --path . res://tests/logic_browser_kern.tscn

const K := preload("res://src/core/browser_kern.gd")
const P := preload("res://src/core/browser_protokoll.gd")
const Lauf := preload("res://src/core/browser_kern_lauf.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	var keep: Dictionary = Config.settings.duplicate(true)
	_fassungen()
	_wahl()
	_zeilen()
	_stummel()
	_quellen()
	_stand()
	await _lauf()
	await _ablauf_quelle()
	_diagnose()
	await _grafik()
	_leitung_kern()
	await _ein_kern()
	await _spotify_sitzung()
	_im_paket()
	Config.settings = keep
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _fassungen() -> void:
	print("Fassungen")
	check(K.fassung("154.3.2") == [154, 3, 2] and K.fassung("151.1") == [151, 1, 0], "Fassung gelesen")
	check(K.fassung("x").is_empty() and K.fassung("1.2.3.4").is_empty() and K.fassung("154").is_empty(), "kaputte Fassung")
	check(K.aelter("151.9.9", "152.0.0") and K.aelter("154.3.2", "154.3.10") and not K.aelter("154.3.2", "154.3.2") and not K.aelter("155.0.0", "154.99.99"), "Vergleich")
	check(K.aelter("x", "151.1.0") and not K.aelter("151.1.0", "x"), "kaputt zählt als kleinste")
	check(K.unter("154.3.2") == "154.3.1" and K.unter("154.3.0") == "154.2.99" and K.unter("155.0.0") == "154.99.99" and K.unter("x") == "", "Fassung darunter (vmax)")
	var rr := K.rueckrufe({ "revoked_versions": [{ "version": "153.1.0" }, { "version_min": "152.0.0", "version_max": "152.2.99" }, "kaputt", { "version": "x" }] })
	check(rr.size() == 2 and K.zurueckgerufen("153.1.0", rr) and K.zurueckgerufen("152.1.5", rr)
			and not K.zurueckgerufen("152.3.0", rr) and not K.zurueckgerufen("153.1.1", rr),
		"Rückrufe gelesen und angewandt")
	check(K.rueckrufe("x").is_empty() and K.rueckrufe({}).is_empty(), "kaputte Rückruf-Liste: leer")
	check(K.meilenstein("154\n") == 154 and K.meilenstein("abc") == 0 and K.meilenstein("150") == 0 and K.meilenstein("99999") == 0, "Meilenstein aus stable.txt")


func _eintrag(f: String, chrom := "154.0.7871.4", abi := "1671cc913eeb4ecf", sha := "a".repeat(40)) -> Dictionary:
	return { "version": f, "file": "cef_binary_%s+g1234abc+chromium-%s_windows64_signed.tar.xz" % [f, chrom], "sha1": sha,
		"last_modified": "2026-10-20T00:00:00.000Z", "abi_hash": abi }


## Eine minimal-Verteilung mit in der Meilenstein-Liste (so steht es 156 nicht da, aber falls künftig).
func _minimal(f: String, chrom := "154.0.7871.4", endung := "tar.bz2", sha := "d".repeat(40), extra := {}) -> Dictionary:
	var e := { "version": f, "file": "cef_binary_%s+g1234abc+chromium-%s_windows64_minimal.%s" % [f, chrom, endung], "sha1": sha, "size": 160000000, "type": "minimal" }
	e.merge(extra, true)
	return e


## Die echte <m>_windows64.json vom PC des Nutzers (156, 2026-10): nur signierte Einträge, ohne size und type.
const ECHT_156 := [
	{ "abi_hash": "3b66cadf26145637", "file": "cef_binary_156.0.14+g4fa4ab5+chromium-156.0.8078.48_windows64_signed.tar.xz",
		"last_modified": "2026-10-24T02:29:39.040000Z", "sha1": "5e7f83e3f7d03d39f6252041abaa1caabda156ff", "version": "156.0.14" },
	{ "abi_hash": "3b66cadf26145637", "file": "cef_binary_156.0.8+g426920c+chromium-156.0.8078.48_windows64_signed.tar.xz",
		"last_modified": "2026-10-23T05:55:53.866000Z", "sha1": "fb197b20f089180045e511ce446280ae671502d0", "version": "156.0.8" },
	{ "abi_hash": "3b66cadf26145637", "file": "cef_binary_156.0.7+g47dbc1d+chromium-156.0.8078.17_windows64_signed.tar.xz",
		"last_modified": "2026-10-22T01:44:36.088000Z", "sha1": "7302ab8fc0f7425b393c408ab04afc4b9c2058d5", "version": "156.0.7" },
]
const B14 := "cef_binary_156.0.14+g4fa4ab5+chromium-156.0.8078.48_windows64"


## Nachgebauter Ausschnitt aus index.json (Aufbau des Hosts: Plattform → versions → files).
func _index(dateien14: Array) -> Dictionary:
	return {
		"linux64": { "versions": [{ "cef_version": "156.0.14+g4fa4ab5+chromium-156.0.8078.48", "files": [
			{ "name": B14 + "_minimal.tar.bz2", "sha1": "9".repeat(40), "size": 1000000, "type": "minimal" }] }] },
		"windows64": { "versions": [
			{ "cef_version": "156.0.14+g4fa4ab5+chromium-156.0.8078.48", "channel": "stable", "chromium_version": "156.0.8078.48", "files": dateien14 },
			{ "cef_version": "156.0.8+g426920c+chromium-156.0.8078.48", "channel": "stable", "files": [
				{ "name": "cef_binary_156.0.8+g426920c+chromium-156.0.8078.48_windows64_minimal.tar.bz2", "sha1": "8".repeat(40), "size": 160000000, "type": "minimal" }] },
		] },
	}


func _d(endung: String, typ: String, sha := "3".repeat(40), groesse: Variant = 170000000) -> Dictionary:
	return { "last_modified": "2026-10-24T02:29:39Z", "name": B14 + endung, "sha1": sha, "size": groesse, "type": typ }


## Das Manifest, das der offizielle Installer im Spiegel liest (0.16.29: „103 … no validated CDN manifest candidates“).
func _manifest(we: Dictionary) -> void:
	print("Manifest für den Installer (Spiegel)")
	check(K.manifest_name(we, 156) == "3b66cadf26145637_windows64.json" and K.manifest_name({ "abi": "" }, 156) == "156_windows64.json"
		and K.manifest_name({ "abi": "../x" }, 156) == "156_windows64.json", "mit ABI-Hash <abi>_windows64.json (BuildAbiHashUrl), sonst <m>_windows64.json")
	check(K.manifest_pruefen(ECHT_156, we) == "", "echte Liste 156: gilt wie im Installer und führt 156.0.14")
	check(K.manifest_pruefen(ECHT_156, K.kandidaten(ECHT_156, [])[2]) == "", "auch für eine ältere Fassung")
	var kaputt := func(feld: String, wert: Variant) -> String:
		var l: Array = (ECHT_156 as Array).duplicate(true)
		if wert == null:
			(l[1] as Dictionary).erase(feld)
		else:
			l[1][feld] = wert
		return K.manifest_pruefen(l, we)
	check(kaputt.call("sha1", null) == "Eintrag 2: sha1" and kaputt.call("sha1", "a".repeat(41)) == "Eintrag 2: sha1",
		"Eintrag ohne/zu lange SHA-1: ganzes Manifest ungültig (wie ParseBuildEntry)")
	check(kaputt.call("file", "a/b.tar.xz") == "Eintrag 2: file" and kaputt.call("file", "x.tar.bz2") == "Eintrag 2: file"
		and kaputt.call("file", ".x.tar.xz") == "Eintrag 2: file"
		and kaputt.call("file", "a..b.tar.xz") == "Eintrag 2: file" and kaputt.call("file", "c:x.tar.xz") == "Eintrag 2: file", "Dateiname wie IsValidArchiveFilename")
	check(kaputt.call("version", "") == "Eintrag 2: version" and kaputt.call("abi_hash", "xyz") == "Eintrag 2: abi_hash" and kaputt.call("last_modified", 5) == "Eintrag 2: last_modified",
		"version, abi_hash (hex), last_modified")
	check(K.manifest_pruefen({ "builds": ECHT_156 }, we) == "keine Liste" and K.manifest_pruefen(null, we) == "keine Liste" and K.manifest_pruefen([1], we) == "Eintrag 1: kein Objekt",
		"kein Listen-Manifest: ungültig")
	var anders: Dictionary = we.duplicate()
	anders["sha1"] = "0".repeat(40)
	var anders_abi: Dictionary = we.duplicate()
	anders_abi["abi"] = "ffffffffffffffff"
	check(K.manifest_pruefen(ECHT_156, anders).contains("fehlt") and K.manifest_pruefen(ECHT_156, anders_abi).contains("fehlt")
		and K.manifest_pruefen([ECHT_156[1]], we).contains("fehlt"), "führt das Manifest unseren Bau nicht genau so: abgelehnt")


func _wahl() -> void:
	print("Wahl des Baus")
	var rr := K.rueckrufe({ "revoked_versions": [{ "version": "154.4.0" }] })
	var liste := { "builds": [_eintrag("154.4.0"), _eintrag("154.3.2"), _eintrag("154.1.0", "154.0.7800.1", "ffffffffffffffff"), _eintrag("150.9.9"), "kaputt",
		{ "version": "154.5.0", "file": "../../evil.tar.xz", "sha1": "b".repeat(40) },
		{ "version": "154.6.0", "file": "cef_binary_154.6.0+g1234abc+chromium-154.0.7871.4_windows64_signed.tar.xz", "sha1": "kurz" },
		{ "version": "154.7.0", "file": "cef_binary_154.3.2+g1234abc+chromium-154.0.7871.4_windows64_signed.tar.xz", "sha1": "c".repeat(40) },
		_minimal("154.3.2")] }
	var w := K.wahl(liste, rr)
	check(w.get("fassung", "") == "154.3.2" and str(w.datei).begins_with("cef_binary_154.3.2+") and w.abi == "1671cc913eeb4ecf" and int(w.groesse) == -1,
		"neueste, nicht zurückgerufene, mit sauberem Dateinamen und Prüfsumme, ohne Größe (%s)" % str(w.get("fassung", "")))
	check(w.get("boot", "") == "cef_binary_154.3.2+g1234abc+chromium-154.0.7871.4_windows64_minimal.tar.bz2" and w.boot_sha1 == "d".repeat(40),
		"steht die minimal-Verteilung mit in der Liste: gleich dazu")
	var ks := K.kandidaten(liste, rr)
	check(ks.map(func(x: Dictionary) -> String: return str(x.fassung)) == ["154.3.2", "154.1.0"] and not (ks[1] as Dictionary).has("boot"), "Kandidaten: neueste zuerst")
	check(K.wahl(liste, rr, "ffffffffffffffff").get("fassung", "") == "154.1.0", "mit festem ABI-Hash nur dessen Generation")
	check(K.wahl(liste, rr, "0000000000000000").is_empty(), "unbekannter ABI-Hash: nichts")
	check(K.wahl({ "builds": [_eintrag("150.9.9")] }, []).is_empty(), "zu alt für Installer und API: nichts")
	check(K.wahl("x", []).is_empty() and K.wahl({ "builds": "x" }, []).is_empty() and K.wahl({}, []).is_empty() and K.wahl([], []).is_empty(), "kaputte Liste: nichts")
	check(K.wahl({ "builds": [_eintrag("154.3.2", "154.0.7871.4", "1671cc913eeb4ecf", "A".repeat(40))] }, []).get("sha1", "") == "a".repeat(40), "Prüfsumme klein geschrieben")
	var gross := _eintrag("154.3.2")
	gross["size"] = K.MAX_ARCHIV + 1
	check(K.wahl({ "builds": [gross] }, []).is_empty(), "signierte größer als %d MB laut Liste: nichts" % (K.MAX_ARCHIV >> 20))
	var viele: Array = []
	for i in 2200:
		viele.append(_eintrag("154.%d.0" % (i % 90)))
	check(not K.wahl({ "builds": viele }, []).is_empty(), "lange Liste: nur die ersten 2000 gelesen, kein Absturz")
	print("Echte Liste 156 (nur signierte)")
	var we := K.wahl(ECHT_156, [])
	check(we.get("fassung", "") == "156.0.14" and we.sha1 == "5e7f83e3f7d03d39f6252041abaa1caabda156ff" and we.abi == "3b66cadf26145637"
		and int(we.groesse) == -1 and not we.has("boot"), "156.0.14 gewählt (0.16.22: „keine Fassung … mit minimal-Verteilung“)")
	check(K.kandidaten(ECHT_156, []).size() == 3 and K.wahl(ECHT_156, [], "3b66cadf26145637").get("fassung", "") == "156.0.14", "alle drei lesbar, ABI-Hash passt")
	check(K.minimal_name(we) == B14 + "_minimal.tar.bz2" and RegEx.create_from_string(K.MINIMAL_RE).search(K.minimal_name(we)) != null and K.minimal_name({}) == "",
		"Name der minimal-Verteilung aus dem signierten")
	print("minimal-Verteilung aus index.json")
	var gut := [_d(".tar.bz2", "standard", "2".repeat(40), 400000000), _d("_minimal.tar.bz2", "minimal"), _d("_client.tar.bz2", "client"),
		_d("_debug_symbols.tar.bz2", "debug_symbols")]
	var mi := K.minimal_aus_index(_index(gut), we)
	check(mi.get("boot", "") == B14 + "_minimal.tar.bz2" and mi.get("boot_sha1", "") == "3".repeat(40) and int(mi.get("boot_groesse", 0)) == 170000000,
		"gefunden: Name, SHA-1, Größe aus dem windows64-Zweig (nicht linux64)")
	check(K.minimal_aus_index(_index(gut), K.kandidaten(ECHT_156, [])[1]).get("boot_sha1", "") == "8".repeat(40), "auch für eine ältere Fassung")
	_manifest(we)
	var mit_xz := gut + [_d("_minimal.tar.xz", "minimal", "4".repeat(40))]
	check(K.minimal_aus_index(_index(mit_xz), we).get("boot_sha1", "") == "4".repeat(40), "beide Formate: xz vor bz2")
	var tolerant := [{ "file": B14 + "_minimal.tar.bz2", "sha1": "5".repeat(40) }]
	var idx_t := _index(tolerant)
	idx_t.windows64.versions[0].erase("cef_version")
	idx_t.windows64.versions[0]["version"] = "156.0.14+g4fa4ab5+chromium-156.0.8078.48"
	var mt := K.minimal_aus_index(idx_t, we)
	check(mt.get("boot_sha1", "") == "5".repeat(40) and int(mt.get("boot_groesse", 0)) == -1, "andere Feldnamen (file, version), ohne Typ und Größe: gelesen")
	print("index.json: Fehlerfälle (mit kurzer Diagnose fürs Protokoll)")
	var ohne := [_d(".tar.bz2", "standard"), _d("_client.tar.bz2", "client")]
	var dg := str(K.minimal_aus_index(_index(ohne), we).get("diagnose", ""))
	check(dg.contains("standard") and dg.contains("client _client.tar.bz2") and dg.length() < 400, "ohne minimal: nennt, was zur Fassung da ist (%s)" % dg)
	var anders: Dictionary = we.duplicate()
	anders["datei"] = "cef_binary_156.0.99+g1111111+chromium-156.0.8078.48_windows64_signed.tar.xz"
	var dg2 := str(K.minimal_aus_index(_index(gut), anders).get("diagnose", ""))
	check(dg2.contains("fehlt") and dg2.contains("2 Fassungen") and dg2.contains("156.0.14+"), "Fassung fehlt im Index: nennt die obersten (%s)" % dg2)
	check(str(K.minimal_aus_index({ "linux64": {} }, we).get("diagnose", "")).contains("linux64") and K.minimal_aus_index("x", we).has("diagnose")
		and K.minimal_aus_index({ "windows64": { "versions": "x" } }, we).has("diagnose"), "ohne windows64-Zweig oder kaputt: Diagnose")
	for fall in [[_d("_minimal.tar.bz2", "standard"), "Typ nicht „minimal“"], [_d("_minimal.tar.bz2", "minimal", "kurz"), "ohne gültige SHA-1"],
			[_d("_minimal.tar.bz2", "minimal", "3".repeat(40), K.MAX_MINIMAL + 1), "größer als %d MB" % (K.MAX_MINIMAL >> 20)],
			[_d("_minimal.tar.bz2", "minimal", "3".repeat(40), "groß"), "kaputte Größe"], [_d("_minimal.zip", "minimal"), "falsche Endung"],
			[_d("_minimal.tar.bz2/../x", "minimal"), "Pfad im Namen"]]:
		check(not K.minimal_aus_index(_index([fall[0]]), we).has("boot"), "minimal %s: nicht genommen" % fall[1])
	var fremd := { "name": "cef_binary_156.0.14+g9999999+chromium-156.0.8078.48_windows64_minimal.tar.bz2", "sha1": "6".repeat(40), "type": "minimal" }
	check(not K.minimal_aus_index(_index([fremd]), we).has("boot"), "minimal eines anderen Commits: nicht genommen")
	check(K.sha1_aus("  " + "AB".repeat(20) + "  x.tar.bz2\n") == "ab".repeat(20) and K.sha1_aus("kaputt") == "" and K.sha1_aus("ab".repeat(32)) == "",
		"SHA-1 aus der .sha1-Beilage")
	print("Wahl: minimal in der Meilenstein-Liste (falls der Host sie künftig dort führt)")
	var mit := func(m: Variant) -> Dictionary: return K.wahl({ "builds": [_eintrag("154.3.2"), m] }, [])
	check((mit.call(_minimal("154.3.2")) as Dictionary).has("boot"), "gleiche Fassung: dazu")
	for fall2 in [[_minimal("154.3.1"), "andere Fassung"], [_minimal("154.3.2", "154.0.7871.5"), "anderes Chromium"],
			[_minimal("154.3.2", "154.0.7871.4", "tar.bz2", "d".repeat(40), { "type": "standard" }), "Typ standard"],
			[_minimal("154.3.2", "154.0.7871.4", "tar.bz2", "d".repeat(40), { "size": K.MAX_MINIMAL + 1 }), "zu groß"],
			[_minimal("154.3.2", "154.0.7871.4", "tar.bz2", "d".repeat(40), { "abi_hash": "ffffffffffffffff" }), "anderer ABI-Hash"]]:
		var r: Dictionary = mit.call(fall2[0])
		check(r.get("fassung", "") == "154.3.2" and not r.has("boot"), "minimal mit %s: signierte ja, Bootstrap später aus index.json" % fall2[1])


func _zeilen() -> void:
	print("Installer-Zeile und Beilagen")
	var z := K.install_zeile("154.3.2", "1671cc913eeb4ecf", "C:\\Users\\x\\AppData\\Local\\Uzai\\browser\\kern\\store", "C:\\Users\\x\\AppData\\Local\\Uzai\\browser\\kern\\spiegel")
	var d: Variant = JSON.parse_string(z)
	check(z.ends_with("\n") and d is Dictionary and d.appid == K.APPID and d.vmin == "154.3.2" and d.vmax == "154.3.2" and d.abi == "1671cc913eeb4ecf",
		"Zeile für --uzai-install: vmin = vmax = die Fassung im Spiegel")
	check(K.install_zeile("x", "", "a", "b") == "" and K.install_zeile("154.3.2", "XYZ", "a", "b") == "", "kaputte Werte: keine Zeile")
	check(K.APPID.length() == 36 and K.APPID.to_upper() == K.APPID, "App-Kennung fest und sauber")
	check(K.sha256_aus("  " + "ab".repeat(32).to_upper() + "  cef_binary.tar.xz\n") == "ab".repeat(32) and K.sha256_aus("kaputt") == "", "SHA-256 aus der Beilage")
	check(K.url_liste(154) == "https://cef-builds.spotifycdn.com/154_windows64.json" and K.url_datei("a.tar.xz").begins_with("https://cef-builds.spotifycdn.com/"), "Adressen nur am festen Host")
	check(K.pruefung_faellig(0, 100) and K.pruefung_faellig(100, 100 + 86400) and not K.pruefung_faellig(100, 100 + 3600) and K.pruefung_faellig(5000, 100), "Update-Prüfung höchstens täglich")
	check(RegEx.create_from_string(K.DATEI_RE).search("cef_binary_154.3.2+g1234abc+chromium-154.0.7871.4_windows64_signed.tar.xz") != null
		and RegEx.create_from_string(K.DATEI_RE).search("cef_binary_154.3.2+g1234abc+chromium-154.0.7871.4_windows64.tar.bz2") == null
		and RegEx.create_from_string(K.DATEI_RE).search("cef_binary_154.3.2+g1234abc+chromium-154.0.7871.4_windows64_signed.tar.xz/../x") == null, "nur signierte xz-Archive nach Muster")
	var mre := RegEx.create_from_string(K.MINIMAL_RE)
	check(mre.search("cef_binary_156.0.14+g4fa4ab5+chromium-156.0.8078.48_windows64_minimal.tar.bz2") != null
		and mre.search("cef_binary_156.0.14+g4fa4ab5+chromium-156.0.8078.48_windows64_minimal.tar.xz") != null
		and mre.search("cef_binary_156.0.14+g4fa4ab5+chromium-156.0.8078.48_windows64.tar.bz2") == null
		and mre.search("cef_binary_156.0.14+g4fa4ab5+chromium-156.0.8078.48_windows64_minimal.tar.gz") == null
		and mre.search("cef_binary_156.0.14+g4fa4ab5+chromium-156.0.8078.48_windows32_minimal.tar.bz2") == null, "minimal-Verteilung nur Windows 64, .tar.bz2 oder .tar.xz")
	check(K._basis("cef_binary_1.2.3+gabcdef0+chromium-1.0.100.1_windows64_signed.tar.xz") == K._basis("cef_binary_1.2.3+gabcdef0+chromium-1.0.100.1_windows64_minimal.tar.bz2")
		and K._basis("x") == "", "gleicher Name bis _windows64")


func _stummel() -> void:
	print("Start-Stummel")
	var ist := FileAccess.get_sha256(K.SHIM)
	var helfer := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	check(ist == K.SHIM_SHA256, "Prüfsumme der Datei stimmt")
	check(helfer.contains(K.SHIM_SHA256), "gleiche Prüfsumme im Helfer")
	var b := FileAccess.get_file_as_bytes(K.SHIM)
	check(b.size() < 65536 and b.size() > 1024 and b[0] == 0x4D and b[1] == 0x5A, "kleine PE-Datei (%d Bytes)" % b.size())
	# Namen stehen hinter Nullbytes: die Nullen zu Leerzeichen, dann als Text suchen.
	var kopie := b.duplicate()
	for i in kopie.size():
		if kopie[i] == 0:
			kopie[i] = 32
	var ascii := kopie.get_string_from_ascii().to_lower()
	check(ascii.contains("runwinmain") and ascii.contains("kernel32.dll") and ascii.contains("mscoree.dll"), "Export RunWinMain, Importe kernel32 und mscoree")
	for nie in ["msvcrt", "ucrtbase", "libcef.dll", "ws2_32", "wininet", "shell32", "advapi32"]:
		check(not ascii.to_lower().contains(nie), "ohne %s" % nie)
	var q := FileAccess.get_file_as_string("res://helper/uzai-browser-start.c")
	check(q.contains("#define UZAI_CEF_API %d" % K.API) and q.contains("hat_schalter(GetCommandLineW(), L\"type\")"), "Quelle: API-Fassung, Unterprozesse ohne .NET")
	check(helfer.contains("'kern-auslegen' { return (Kern-Auslegen $a) }") and helfer.contains("function Kern-SignaturEntfernen") and helfer.contains("'kern-ressource' { return (Kern-Ressource $a) }"),
		"Helfer: auslegen, Signatur aus Kopien, Ressource")
	check(helfer.contains("install_path = (Join-Path (Kern-Wurzel) 'store')") and helfer.contains("launch_health = 'explicit'"), "Helfer schreibt Store und Gesundheitsmodus in die Ressource")


func _quellen() -> void:
	print("Kern-Quelltext")
	var kern := FileAccess.get_file_as_string("res://helper/uzai-browser-kern.cs")
	var tab: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cef_api_15101.json"))
	check(tab is Dictionary and int(tab.api) == K.API, "Tabelle der C-Schnittstelle für API %d" % K.API)
	check(kern.contains("public const int API = %d;" % K.API) and kern.contains('API_HASH = "%s"' % str(tab.hash_windows)), "Kern: API-Fassung und Hash wie die Tabelle")
	for muss in ["SETTINGS_NO_SANDBOX, 0)", "SETTINGS_REMOTE_DEBUGGING_PORT, 0)", "SETTINGS_COMMAND_LINE_ARGS_DISABLED, 1)", "kern_sandbox", "kern_signatur",
			"UzbSignatur.Von(start.LibcefPfad, UzcV.CEF_ZERTIFIKAT)", "RUNTIME_STYLE_ALLOY", "\"disable-component-update\"", "launch_success"]:
		check(kern.contains(muss), "Kern: %s" % muss)
	for nie in ["Process.Start", "execute_java_script", "show_dev_tools", "remote-debugging-port=", "no_sandbox = 1"]:
		check(not kern.contains(nie), "Kern ohne %s" % nie)
	check(kern.contains('"3906F72B1D5FA45A6334A8590495FAEB93347E5B"'), "Fingerabdruck des CEF-Zertifikats")


func _stand() -> void:
	print("Stand und Leitung")
	Config.set_value("browser.kern_fassung", "")
	check(not K.bereit(), "ohne Fassung nicht bereit")
	K.merken("154.3.2", "1671cc913eeb4ecf")
	check(K.bereit() and K.stand().fassung == "154.3.2" and not bool(K.stand().gesund), "gemerkt")
	K.vergessen("kern_api")
	check(not K.bereit() and K.stand().fehler == "kern_api", "vergessen mit Grund")
	for b in [["gliederung", { "tab": 1 }], ["springe", { "tab": 1, "id": 3 }], ["wahl-setzen", { "tab": 1, "id": 3, "index": 2 }],
			["feld-weiter", { "tab": 1, "id": 3, "richtung": -1 }],
			["suche", { "tab": 1, "text": "hallo" }], ["blocker", { "tab": 1, "an": false }], ["blocker-liste", { "hosts": ["a.de", "b.de"] }], ["kern", { "aktion": "gesund" }],
			["video", { "tab": 1, "aktion": "stumm" }]]:
		check(P.befehl(b[0], b[1]) != "", "Befehl %s passt ins Schema" % b[0])
	check(P.befehl("kern", { "aktion": "sprengen" }) == "" and P.befehl("wahl-setzen", { "tab": 1, "id": 3, "index": 400 }) == "", "falsche Werte gehen nie raus")
	var e := P.ereignis(JSON.stringify({ "t": "kern", "stand": "laedt", "schritt": "downloading", "prozent": 42, "fassung": "", "text": "x\u202ey" }))
	check(e.get("prozent", -1) == 42 and e.get("text", "") == "xy", "kern-Ereignis geprüft und gesäubert")
	var g := P.ereignis(JSON.stringify({ "t": "gliederung", "tab": 1, "punkte": [[1, 0, 1, "Titel"], [2, 900, 2, "Teil"]] }))
	check(not g.is_empty() and (g.punkte as Array).size() == 2 and g.punkte[1][3] == "Teil", "Gliederung geprüft")
	check(P.ereignis(JSON.stringify({ "t": "gliederung", "tab": 1, "punkte": [[1, 0, 9, "x"]] })).is_empty(), "Gliederung mit falscher Stufe verworfen")


## Der Lauf im Hintergrund (gespielt): Fortschritt steigt, stand() für Bühne und Dialog, Abbruch, nur ein Lauf zugleich.
func _lauf() -> void:
	print("Einrichten im Hintergrund")
	check(not Lauf.noetig(), "ohne Windows: nichts von selbst zu laden")
	Lauf.automatisch()
	check(not Lauf.aktiv(), "von selbst: startet ohne Windows nicht")
	var l: Node = Lauf.starten(true)
	check(l != null and Lauf.starten(true) == l, "ein Lauf zugleich")
	var anteile: Array = []
	l.connect("fortschritt", func(_s: String, _p: int, a: float) -> void: anteile.append(a))
	var grund: String = await l.fertig
	var steigend := true
	for i in range(1, anteile.size()):
		steigend = steigend and float(anteile[i]) >= float(anteile[i - 1]) - 0.0001
	check(grund == "" and anteile.size() >= 8 and steigend and float(anteile[-1]) > 0.99, "gespielt: fertig, Balken steigt bis voll (%d Schritte)" % anteile.size())
	var st := Lauf.stand()
	check(bool(st.fertig) and not bool(st.laeuft) and str(st.fehler) == "", "Stand nach dem Ende: fertig")
	var l2: Node = Lauf.starten(true)
	await get_tree().create_timer(0.8).timeout
	check(Lauf.aktiv() and bool(Lauf.stand().laeuft) and float(Lauf.stand().anteil) > 0.0, "läuft: Stand mit Schritt und Anteil")
	l2.call("abbrechen")
	var g2: String = await l2.fertig
	check(g2 == Lauf.ABGEBROCHEN and Lauf.abgebrochen and str(Lauf.stand().fehler) == Lauf.ABGEBROCHEN, "Abbruch: nichts installiert, in dieser Sitzung nicht von selbst neu")
	Lauf.abgebrochen = false
	check(Lauf.VON.install < Lauf.BIS.install and Lauf.BIS.download == Lauf.VON.pruefen and Lauf.BIS.install == 1.0, "Balken-Abschnitte schließen lückenlos an")
	var r: String = await K.laden(func(_a: String, _b: int) -> void: pass, func(_a: String, _b: String) -> Dictionary: return {})
	check(r != "", "laden() ohne Windows: Grund statt Versuch")
	print("Dateien neben dem Helfer, Protokoll")
	check(K.dateien_auslegen() == "", "Stummel, Filterliste, Skripte und Quellen neben den Helfer (vor kern-auslegen)")
	var dir := Config.path("helper/browser")
	check(FileAccess.get_sha256(dir.path_join("uzai-browser-start.dll")) == K.SHIM_SHA256 and FileAccess.get_sha256(dir.path_join("filter.gz")) == K.FILTER_SHA256
		and FileAccess.file_exists(dir.path_join("uzai-browser-kern.cs")), "liegen mit Prüfsumme dort")
	K.protokoll("Probe\nZeile")
	var log := FileAccess.get_file_as_string(Config.path(K.LOG))
	check(log.contains("Probe") and not log.contains("Probe\nZeile".c_unescape()), "Protokoll: eine Zeile je Eintrag, ohne Steuerzeichen")
	var home := OS.get_environment("USERPROFILE")
	check(K.anonym("x" + home + "y") == ("x%USERPROFILE%y" if home.length() > 3 else "x" + home + "y") and K.anonym("a".repeat(900)).length() == 400, "ohne Benutzerpfad, gekürzt")


## 0.16.37: neue Kern-Prozesse, während alte noch liefen; ein sauberes Ende (0) galt als „absturz“; Controller-Eingaben
## kamen nicht an (Uzai nahm sie ohne Fensterfokus nicht an). Jetzt: höchstens ein Kern, Ende mit Warten, Pad ohne Fokus.
## Spotify-Sitzung: eigener Kern (--uzai-spotify), nicht in der Regel „ein Kern je Uzai“; der Schlüssel kommt
## über Leitung und Schema (hier vom nachgebauten Kern, browser_demo.gd), ohne Netz.
func _spotify_sitzung() -> void:
	print("Spotify-Sitzung")
	var Web := load("res://src/core/spotify_web.gd")
	var W := load("res://src/core/browser_wirt.gd")
	var web: Node = Web.new()
	add_child(web)
	var vor := (W.laufend as Array).size()
	var r: Dictionary = await web.call("holen", 5.0)
	check(bool(r.get("ok", false)) and str(r.get("token", "")) == "VorfuehrungSchluessel0123456789", "Schlüssel der Seite über Leitung und Schema")
	check((W.laufend as Array).size() == vor, "die Sitzung zählt nicht als Browser-Kern (eigener Ordner, kein Warten)")
	check(bool(web.call("laeuft")), "kurzer Nachlauf nach dem Schlüssel")
	await web.call("stoppen")
	await get_tree().create_timer(0.2).timeout
	check(not bool(web.call("laeuft")), "danach ist der Kern der Sitzung zu")
	web.set("anmeldung_offen", true)
	var r2: Dictionary = await web.call("holen", 1.0)
	check(not bool(r2.ok) and str(r2.why) == "anmeldung", "Anmeldeseite offen: kein zweiter Kern auf demselben Ordner")
	web.set("anmeldung_offen", false)
	web.queue_free()
	await _spotify_bruecke()
	var wq := FileAccess.get_file_as_string("res://src/core/browser_wirt.gd")
	check(wq.contains("\"--uzai-spotify\" if spotify else \"--uzai-kern\"") and wq.contains("if not self in laufend and not spotify:")
			and wq.contains("func _nach_start() -> void:\n\tif spotify:\n\t\treturn"), "Wirt: Start als Spotify-Sitzung, ohne Kern-Pflege")
	var b := FileAccess.get_file_as_string("res://src/ui/layers/browser.gd")
	check(b.contains("and not spotify:\n\t\tt.besucht = t.url") and b.contains("if not spotify:\n\t\t\t\t_karussell()") and b.contains("if spotify:\n\t\t_spotify_menu()"),
			"Anmeldeseite: kein Verlauf, keine Tabs, eigenes kleines Menü")


## Abfragen IN der Seite über den nachgebauten Kern (browser_demo.gd): hin und zurück über Leitung und Schema,
## Zeitlimit, Größengrenze, falscher Host abgelehnt, gebündelt, Anmeldeseite zuerst, Leerlauf beendet den Kern.
func _spotify_bruecke() -> void:
	print("Spotify-Sitzung: Abfragen in der Seite")
	var Web := load("res://src/core/spotify_web.gd")
	var Demo := load("res://src/core/browser_demo.gd")
	var W := load("res://src/core/browser_wirt.gd")
	var zeilen: Array = []
	var web: Node = Web.new()
	web.set("log_fn", func(t: String) -> void: zeilen.append(t))
	add_child(web)
	var pf := JSON.stringify({ "operationName": "profileAttributes", "variables": {}, "extensions": { "persistedQuery": { "version": 1, "sha256Hash": "b".repeat(64) } } })
	Demo.spotify_abfragen.clear()
	var r: Dictionary = await web.call("abfrage", "pathfinder", "POST", P.PATHFINDER_PFAD, pf)
	check(int(r.code) == 200 and str(r.text).contains("vorfuehrung") and bool(web.call("laeuft")), "Kern gestartet, Abfrage hin und zurück (Kennung, Schema)")
	check(Demo.spotify_abfragen.size() == 1 and str(Demo.spotify_abfragen[0].ziel) == "pathfinder", "eine Abfrage in der Seite angekommen")
	Demo.spotify_antwort = func(_z: String, _m: String, pfad: String, _i: String) -> Dictionary:
		if pfad.contains("still"):
			return { "still": true }
		if pfad.contains("gross"):
			return { "code": 200, "text": "x".repeat(P.MAX_ANTWORT + 5) }
		if pfad.contains("langsam"):
			return { "code": 200, "text": "{}", "nach_s": 0.3 }
		return { "code": 403, "text": "{\"error\":{\"message\":\"nein BQDgeheimgeheimgeheimgeheim\"}}" }
	var t0 := Time.get_ticks_msec()
	var rz: Dictionary = await web.call("abfrage", "webapi", "GET", "/v1/still", "", "", 1.0)
	check(int(rz.code) == 0 and str(rz.grund) == "zeit" and Time.get_ticks_msec() - t0 < 6000, "Zeitlimit: keine Antwort → „zeit“ nach %d ms" % (Time.get_ticks_msec() - t0))
	var rg: Dictionary = await web.call("abfrage", "webapi", "GET", "/v1/gross")
	check(bool(rg.gekuerzt) and str(rg.text).length() == P.MAX_ANTWORT, "Größengrenze: gekürzt auf %d Zeichen" % P.MAX_ANTWORT)
	var n0: int = Demo.spotify_abfragen.size()
	var rf: Dictionary = await web.call("abfrage", "webapi", "GET", "//boese.example/v1/x")
	var rf2: Dictionary = await web.call("abfrage", "pathfinder", "GET", P.PATHFINDER_PFAD)
	var rf3: Dictionary = await web.call("abfrage", "spclient", "GET", "/melody/v1/x")
	check(str(rf.grund) == "ziel" and str(rf2.grund) == "ziel" and str(rf3.grund) == "ziel" and Demo.spotify_abfragen.size() == n0,
			"falscher Host, falsche Methode, fremder Dienst: abgelehnt, nie in der Seite")
	var r403: Dictionary = await web.call("abfrage", "webapi", "GET", "/v1/me")
	check(int(r403.code) == 403 and zeilen.any(func(z: String) -> bool: return z.contains("Seite → webapi /v1/me: HTTP 403 – ") and not z.contains("BQDgeheim")),
			"Diagnose: HTTP-Code je Art, Fehlertext ohne Schlüssel")
	# Gebündelt: zehn gleichzeitig, höchstens GLEICHZEITIG in der Seite.
	var stand := { "fertig": 0, "hoch": 0 }
	for i in 10:
		var f := func() -> void:
			var rr: Dictionary = await web.call("abfrage", "webapi", "GET", "/v1/langsam/%d" % i)
			if int(rr.code) == 200:
				stand.fertig = int(stand.fertig) + 1
		f.call()
	var bis := Time.get_ticks_msec() + 8000
	while int(stand.fertig) < 10 and Time.get_ticks_msec() < bis:
		stand.hoch = maxi(int(stand.hoch), int(web.get("_aktiv")))
		await get_tree().process_frame
	check(int(stand.fertig) == 10 and int(stand.hoch) <= int(Web.GLEICHZEITIG) and int(stand.hoch) >= 2, "zehn gleichzeitig: alle beantwortet, höchstens %d auf einmal (%d)" % [Web.GLEICHZEITIG, int(stand.hoch)])
	# Anmeldeseite offen: Abfragen laufen in ihrer Seite; geht sie zu, übernimmt der eigene Kern.
	await web.call("stoppen")
	var aw: Node = W.new()
	aw.set("spotify", true)
	add_child(aw)
	aw.ereignis.connect(func(e: Dictionary) -> void:
		if str(e.get("t", "")) == "spotify-antwort":
			web.call("antwort", e))
	aw.call("starten", "Test: Anmeldeseite")
	await get_tree().process_frame
	aw.call("senden", "tab-neu", { "url": Web.WEB_URL, "privat": false, "vorn": true, "nutzer": false })
	web.call("anmeldung_start", aw)
	Demo.spotify_antwort = Callable()
	var ra: Dictionary = await web.call("abfrage", "pathfinder", "POST", P.PATHFINDER_PFAD, pf)
	check(int(ra.code) == 200 and not bool(web.call("laeuft")), "Anmeldeseite offen: Abfrage in ihrer Seite (kein zweiter Kern)")
	aw.call("beenden", "Test")
	await web.call("anmeldung_beendet", aw)
	var rb: Dictionary = await web.call("abfrage", "pathfinder", "POST", P.PATHFINDER_PFAD, pf)
	check(int(rb.code) == 200 and bool(web.call("laeuft")), "danach der eigene Kern")
	# Leerlauf: ohne Abfragen geht der Kern zu (kein Prozess bleibt dauerhaft).
	web.set("leerlauf_s", 0.4)
	await web.call("abfrage", "pathfinder", "POST", P.PATHFINDER_PFAD, pf)
	web.call("_leerlauf")
	await get_tree().create_timer(1.5).timeout
	check(not bool(web.call("laeuft")) and zeilen.any(func(z: String) -> bool: return z.contains("ohne Abfrage, Kern zu")), "Leerlauf: Kern beendet")
	# Rückfall: Kern ohne Seite (Anmeldeseite hängt) – die Abfrage endet sofort, nichts blockiert.
	web.set("anmeldung_offen", true)
	web.set("anmelde_wirt", null)
	web.set("anmeldung_warten_s", 0.5)
	web.set("_kern_aus_bis", 0)
	t0 = Time.get_ticks_msec()
	var rr2: Dictionary = await web.call("abfrage", "webapi", "GET", "/v1/me")
	check(int(rr2.code) == 0 and str(rr2.grund) == "welt" and Time.get_ticks_msec() - t0 < 3000, "Rückfall: keine Seite → „welt“, nichts wartet länger")
	web.set("anmeldung_offen", false)
	Demo.spotify_antwort = Callable()
	await web.call("stoppen")
	web.queue_free()
	check(Web.fehler_kurz("abc BQD1234567890abcdefXYZ spotify:track:4uLU6hMCjMI75M1A2tKUQC lena@example.com\n x").find("BQD") < 0
			and not Web.fehler_kurz("spotify:track:4uLU6hMCjMI75M1A2tKUQC").contains("4uLU") and not Web.fehler_kurz("lena@example.com").contains("lena")
			and Web.fehler_kurz("y".repeat(500)).length() <= 120, "Fehlertext gesäubert (Schlüssel, Kennung, E-Mail), höchstens 120 Zeichen")
	check(Web.art_von("spclient", "/connect-state/v1/devices/hobs_0123456789abcdef", "") == "connect-state/devices"
			and Web.art_von("webapi", "/v1/playlists/37i9dQZF1DXcBWIGoYBM5M/tracks", "") == "/v1/playlists/…", "Art fürs Protokoll ohne Kennungen")
	check(Web.aus_antwort({ "t": "spotify-antwort", "id": 1, "code": 200, "grund": "", "text": "x", "gekuerzt": false, "warte": 0 }).size() == 6
			and Web.aus_antwort({ "t": "spotify-antwort", "id": 1, "code": 200, "grund": "boese", "text": "x", "gekuerzt": false, "warte": 0 }).is_empty()
			and Web.aus_antwort({ "t": "spotify-antwort", "id": 1, "code": 200, "grund": "", "text": 5, "gekuerzt": false, "warte": 0 }).is_empty(),
			"zweite Mauer für die Antwort")


func _ein_kern() -> void:
	print("Ein Kern je Sitzung")
	var W := load("res://src/core/browser_wirt.gd")
	var halter := Node.new()
	add_child(halter)
	var w1: Node = W.new()
	w1.set("demo", true)
	halter.add_child(w1)
	var s0 := int(W.sitzungen)
	w1.call("starten")
	await get_tree().process_frame
	check(bool(w1.get("bereit")) and W.laufend.size() == 1, "erster Kern läuft")
	var w2: Node = W.new()
	w2.set("demo", true)
	add_child(w2)
	w2.call("starten", "Test: zweiter Start")
	await get_tree().create_timer(0.3).timeout
	check(not bool(w2.get("bereit")) and W.laufend.size() == 1 and int(W.doppelt) >= 1, "zweiter Start wartet, solange der erste läuft")
	w1.call("beenden", "Test")
	check(w1.get_parent() == get_tree().root, "beim Beenden hängt sich der Wirt an die Wurzel (die Ebene darf weg)")
	halter.free()
	await get_tree().create_timer(0.4).timeout
	check(not is_instance_valid(w1) and bool(w2.get("bereit")) and W.laufend.size() == 1 and W.laufend[0] == w2, "erster weg, dann startet der zweite")
	check(int(W.sitzungen) == s0 + 2, "Sitzungen gezählt")
	w2.call("beenden", "Test")
	await get_tree().create_timer(0.2).timeout
	check(W.laufend.is_empty(), "nach dem Ende kein Kern mehr")
	var wq := FileAccess.get_file_as_string("res://src/core/browser_wirt.gd")
	var pa := wq.substr(wq.find("func _prozess_aus()"), 2400)
	check(pa.find("if _beenden:") < pa.find("_protokoll_reste(") and pa.contains("(code & 0xFFFFFFFF) == 0") and pa.contains("beendet.emit(\"kern_ende\")"),
		"Ende auf Wunsch still, Rückgabe 0 ohne Wunsch kein „absturz“")
	check(pa.contains("Time.get_ticks_msec() - _start_ms"), "„endete nach … s“ zählt ab dem Start des Prozesses (nicht ab Uzais Start)")
	check(wq.contains("_zaehlen(\"→\" + art)") and wq.contains("_zaehlen(\"←\" + str(e.t))") and wq.contains("\"Leitung gesamt (%s): %s\""),
		"Leitung: alle Befehle/Ereignisse gezählt je Art, im Protokoll")
	var b := FileAccess.get_file_as_string("res://src/ui/layers/browser.gd")
	check(b.contains("wirt.beenden(") and not b.contains("wirt.senden(\"ende\")\n\tif is_instance_valid(main)"), "Browser zu: Kern sauber beenden")
	var zs := b.substr(b.find("func _zeige_seite()"), 600)
	check(zs.contains("_pad_ohne_fokus(true)") and b.contains("Nav.pad_unfocused = true") and b.substr(b.find("func close()"), 300).contains("_pad_ohne_fokus(false)"),
		"Seite offen: Controller geht an den Browser, auch wenn das Fenster des Kerns den Fokus hat")
	check(b.contains("str(z.art) == \"rahmen\"") and P.ARTEN.has("rahmen"), "Rahmen (iframe, Cookie-Banner): A schaltet den Zeiger ein")
	var js := FileAccess.get_file_as_string("res://helper/uzai-browser-karte.js")
	check(js.contains("rahmen: 8") and js.contains("if (tag === 'IFRAME') return ARTEN.rahmen;") and P.ARTEN.find("rahmen") == 8, "Sprung-Skript meldet Rahmen als Art 8")
	var g := FileAccess.get_file_as_string("res://helper/uzai-browser-gemeinsam.cs")
	check(g.contains("{ 0, 8 }, { 0, 6 } };") and g.contains("\"sonst\", \"rahmen\" };"), "Schema im Kern: Art bis 8")
	var kq := FileAccess.get_file_as_string("res://helper/uzai-browser-kern.cs")
	check(kq.contains("Cdp(t, \"Page.enable\"") and kq.contains("\"ohne-welt\"") and kq.contains("\"stumm\"") and kq.contains("\"hallo\", 0, \"\", \"Tab "),
		"Kern meldet: Einrichtung der Welt, erstes hallo, Befehle ohne Welt, stumme Seite")


## Attrappe der Kern-Leitung: nimmt, was der Wirt an den Kern schickt (wie browser_demo.gd, nur zum Mitschreiben).
class Leitung extends RefCounted:
	var befehle: Array = []
	func verbinden(_cb: Callable) -> void:
		pass
	func befehl(v: Variant) -> void:
		befehle.append(v)
	func schritt(_dt: float) -> void:
		pass


## Uzai → Wirt → Kern und zurück, ohne Windows: die Zeilen, die der echte CEF-Kern schickt (0.16.36: „bereit“ mit
## „2 cef 156.0.15+g…+chromium-…“ war länger als das Schema erlaubte – der Kern verwarf es selbst, Uzai wartete 60 s
## und schickte nie einen Befehl), dann die Befehle der Controller-Steuerung bis zur Leitung.
func _leitung_kern() -> void:
	print("Leitung zum CEF-Kern (Attrappe)")
	var W := load("res://src/core/browser_wirt.gd")
	var w: Node = W.new()
	var l := Leitung.new()
	w.set("demo", false)
	w.set("_sim", l)
	var ereignisse: Array = []
	w.connect("ereignis", func(e: Dictionary) -> void: ereignisse.append(str(e.t)))
	var alt_pruefung: Variant = Config.get_value("browser.kern_pruefung", 0)
	Config.set_value("browser.kern_pruefung", int(Time.get_unix_time_from_system()))
	w.call("_zeile", JSON.stringify({ "t": "kern", "stand": "info", "schritt": "schalter", "prozent": 0, "fassung": "", "text": "grafik=hardware; entfernt: -; 13 Aus-Schalter" }))
	w.call("_zeile", JSON.stringify({ "t": "bereit", "version": "2 cef 156.0.15+g1e9b8f1+chromium-156.0.8078.48" }))
	check(bool(w.get("bereit")) and str(w.get("kern_fassung")).begins_with("2 cef 156.0.15") and "bereit" in ereignisse, "„bereit“ des echten Kerns kommt an")
	var kern := FileAccess.get_file_as_string("res://helper/uzai-browser-kern.cs")
	var v := kern.substr(kern.find("void KontextBereit(IntPtr self)"), 400)
	var max_v := ("%s cef " % "2").length() + 80
	check(v.contains("UzcApi.Utf8(UzcApi.cef_version_full(), 80)") and max_v <= int(P.EREIGNISSE.bereit.version[1]) and kern.contains("public const string VERSION = \"2\";"),
		"Kern: Fassung höchstens %d Zeichen, Schema erlaubt %d" % [max_v, int(P.EREIGNISSE.bereit.version[1])])
	var gd := FileAccess.get_file_as_string("res://helper/uzai-browser-gemeinsam.cs")
	check(gd.contains("{ \"bereit\", new[] { \"version=text:%d\" } }," % int(P.EREIGNISSE.bereit.version[1])), "gleiche Grenze im Schema des Kerns")
	# Controller-Steuerung: dieselben Befehle wie die Oberfläche (browser.gd), alle bis zur Leitung.
	var steuer := [
		["tab-neu", { "url": "https://www.google.com/", "privat": false, "vorn": true, "nutzer": true }],
		["fenster", { "x": 0, "y": 0, "w": 1920, "h": 1080 }], ["zeigen", { "an": true }],
		["springe", { "tab": 1, "id": 3 }], ["fokus", { "tab": 1, "id": 3 }], ["aktivieren", { "tab": 1, "id": 3, "neu": false }],
		["zeiger", { "tab": 1, "x": 640, "y": 360 }], ["klick", { "tab": 1, "x": 640, "y": 360 }], ["rollen", { "tab": 1, "vx": 0, "vy": 900 }],
		["rad", { "tab": 1, "x": 640, "y": 360, "dy": -120 }], ["text", { "tab": 1, "id": 4, "text": "uzai" }], ["taste", { "tab": 1, "taste": "enter" }],
		["zurueck", { "tab": 1 }], ["zoom", { "tab": 1, "prozent": 125 }], ["tab-wahl", { "tab": 1 }], ["gliederung", { "tab": 1 }],
		["feld-weiter", { "tab": 1, "id": 4, "richtung": 1 }], ["video", { "tab": 1, "aktion": "pause" }],
	]
	var gut := 0
	for b in steuer:
		gut += 1 if bool(w.call("senden", b[0], b[1])) else 0
	var arten: Array = l.befehle.map(func(x: Variant) -> String: return str((x as Dictionary).get("t", "")) if x is Dictionary else "")
	var fehlt: Array = steuer.filter(func(b: Array) -> bool: return not (str(b[0]) in arten))
	check(gut == steuer.size() and fehlt.is_empty(), "Controller-Befehle erreichen den Kern (%d/%d) %s" % [gut, steuer.size(), str(fehlt.map(func(b: Array) -> String: return b[0]))])
	var kq := FileAccess.get_file_as_string("res://helper/uzai-browser-kern.cs")
	var unbekannt: Array = []
	for b in steuer:
		if not (kq.contains("case \"%s\"" % b[0]) or kq.contains("art == \"%s\"" % b[0])):
			unbekannt.append(b[0])
	check(unbekannt.is_empty(), "jeden dieser Befehle verarbeitet der CEF-Kern %s" % str(unbekannt))
	# Antworten des Kerns (Tab, Sprungkarte, Feld) gehen an die Oberfläche; Kaputtes wird gezählt, nicht geschluckt.
	w.call("_zeile", JSON.stringify({ "t": "tab", "tab": 1, "url": "https://www.google.com/", "titel": "Google", "laedt": false, "zurueck": false, "vor": false,
		"zoom": 100, "privat": false, "aktiv": true }))
	w.call("_zeile", JSON.stringify({ "t": "karte", "tab": 1, "vw": 1280, "vh": 720, "sy": 0, "sh": 900, "ziele": [[1, 10, 20, 100, 30, 0, 2, "Suche"]] }))
	w.call("_zeile", JSON.stringify({ "t": "bereit", "version": "x".repeat(200) }))
	check("tab" in ereignisse, "Tab-Stand kommt an")
	check((w.get("_verworfene") as Array).has("bereit"), "verworfenes Ereignis (zu lang) wird je Art gemerkt und protokolliert")
	check(int(w.get("_letzte_zeile")) > 0, "jede Zeile hält die Wartezeit bis „bereit“ offen (Z1 erst nach 60 s Stille)")
	var log := FileAccess.get_file_as_string(Config.path(K.LOG))
	check(log.contains("Browser bereit nach") and log.contains("Leitung: Ereignis vom Kern verworfen (Schema): bereit"), "Protokoll: Zeitpunkt von „bereit“, Verworfenes")
	w.call("_leitung_schreiben")
	log = FileAccess.get_file_as_string(Config.path(K.LOG))
	check(log.contains("Leitung (erste 12): ←kern ←bereit →tab-neu") and not log.contains("google.com"), "Protokoll: erste Befehle/Ereignisse nur als Art, ohne Adressen")
	Config.set_value("browser.kern_pruefung", alt_pruefung)
	w.free()


## 0.16.35: „GPU process isn't usable“ – der Stummel lehnte jeden Unterprozess ab (Pfadprüfung um ein Zeichen falsch,
## tests/kern_stummel_probe.sh). Dazu der Rückfall auf Software-Grafik und das Erneuern eines alten Stummels.
func _grafik() -> void:
	print("Grafik-Rückfall und Start-Stummel")
	var W := load("res://src/core/browser_wirt.gd")
	check(W.gpu_unbrauchbar("[1101/100153.1:FATAL:content\\browser\\gpu\\gpu_data_manager_impl_private.cc:389] GPU process isn't usable. Goodbye.")
		and not W.gpu_unbrauchbar("") and not W.gpu_unbrauchbar("GPU process exited unexpectedly"), "„GPU process isn't usable“ aus stderr erkannt")
	var alt: Variant = Config.get_value("browser.kern_grafik", "hardware")
	check(str(Config.DEFAULTS.browser.kern_grafik) == "hardware" and W.grafik() == "hardware", "Standard: Hardware")
	Config.set_value("browser.kern_grafik", "software")
	var sw: String = W.grafik()
	Config.set_value("browser.kern_grafik", "irgendwas")
	check(sw == "software" and W.grafik() == "hardware", "Software gemerkt, Unbekanntes zählt als Hardware")
	Config.set_value("browser.kern_grafik", alt)
	var wq := FileAccess.get_file_as_string("res://src/core/browser_wirt.gd")
	var es := wq.substr(wq.find("func _echt_starten()"), 2400)
	check(es.find("Kern.stummel_auffrischen()") > 0 and es.find("Kern.stummel_auffrischen()") < es.find("\"kern-bauen\"") and es.contains("args.append(\"--grafik=software\")"),
		"vor dem Start: alter Stummel erneuert, Grafik als Argument")
	var pa := wq.substr(wq.find("func _prozess_aus()"), 1600)
	check(pa.contains("gpu_unbrauchbar(") and pa.contains("not _software_versucht") and pa.contains("Config.set_value(\"browser.kern_grafik\", \"software\")")
		and pa.contains("_echt_starten()"), "GPU unbrauchbar: einmal je Sitzung neu mit Software, gemerkt")
	var kq := FileAccess.get_file_as_string("res://src/core/browser_kern.gd")
	var sa := kq.substr(kq.find("static func stummel_auffrischen()"), 1400)
	check(sa.contains("FileAccess.get_sha256(kl) == SHIM_SHA256") and sa.contains("FileAccess.get_sha256(SHIM) != SHIM_SHA256") and sa.contains("\"kern-ressource\""),
		"Stummel neben dem Kern: nur geprüfter Stummel, danach die Konfiguration neu")
	var r: String = await K.stummel_auffrischen()
	check(r == "", "ohne Kern-Ordner: nichts zu tun")
	var c := FileAccess.get_file_as_string("res://helper/uzai-browser-start.c")
	check(c.contains("const wchar* ende = pfad + n - 11;"), "Stummel: „\\libcef.dll“ mit 11 Zeichen verglichen")
	var b := FileAccess.get_file_as_string("res://src/ui/layers/browser.gd")
	check(b.contains("zeile.call(\"monitor\", \"Grafik\", grafik,") and b.contains("Config.set_value(\"browser.kern_grafik\", str(v))"), "Menü Browser-Kern: Grafik umstellbar")


## Startet der Kern nicht, steht der Grund mit Code im Protokoll und als „Code: …“ im Hinweis (0.16.33: nur
## „Browser startet nicht“ ohne jeden Hinweis).
func _diagnose() -> void:
	print("Diagnose, wenn der Kern nicht startet")
	var W := load("res://src/core/browser_wirt.gd")
	check(str(W.ausgang_text(0x80000003)).begins_with("0x80000003 Abbruch im Bootstrap") and W.ausgang_text(-2147483645) == W.ausgang_text(0x80000003),
		"Absturz-Code auch als negative Zahl gelesen (%s)" % W.ausgang_text(-2147483645))
	check(str(W.ausgang_text(204)).contains("S204") and str(W.ausgang_text(14)).contains("K14") and str(W.ausgang_text(103)).contains("Installer")
		and W.ausgang_text(-1) == "Rückgabewert unbekannt" and W.ausgang_text(12345) == "12345" and str(W.ausgang_text(0xC0000135)).contains("DLL fehlt"),
		"Kern-, Stummel-, Installer- und Windows-Codes benannt")
	check(W._kurz("K14 cef_initialize, CEF-Code 21") == "K14" and W._kurz("") == "" and W._kurz("x".repeat(40)).length() == 16, "kurzer Code vorn")
	var w: Node = W.new()
	w.call("_scheitern", "start", "H1 kern-bauen: start")
	check(str(w.get("diagnose")) == "start H1" and str(w.get("fehler")) == "start", "Code für den Hinweis: Grund und Kurzcode")
	w.set("_grund", "K14 cef_initialize, CEF-Code 21")
	w.call("_scheitern", "absturz")
	check(str(w.get("diagnose")) == "absturz K14", "ohne eigenen Grund: der letzte vom Kern")
	w.free()
	var wq := FileAccess.get_file_as_string("res://src/core/browser_wirt.gd")
	check(wq.contains("OS.get_process_exit_code(_pid)") and wq.contains("_protokoll_reste(") and wq.contains("app/debug.log") and wq.contains("START_ZEIT_S"),
		"Wirt: Rückgabewert, stderr, debug.log des Bootstraps, Zeitgrenze bis „bereit“")
	var b := FileAccess.get_file_as_string("res://src/ui/layers/browser.gd")
	check(b.contains("_mit_code(\"Uzai neu starten und nochmal versuchen.\")") and b.contains("if str(e.schritt) != \"grund\":"), "Hinweis mit Code, Gründe ohne zweiten Hinweis")
	var k := FileAccess.get_file_as_string("res://helper/uzai-browser-kern.cs")
	var lauf := k.substr(k.find("static int Lauf(string arg)"), 5000)
	check(lauf.count("Grund(aus, \"K") >= 10 and k.contains("UzcApi.cef_get_exit_code().ToString(") and k.contains("Grund(new UzbAusgabe(Console.OpenStandardOutput()), \"K3 \""),
		"Kern: jeder Abbruch mit Code K… (cef_initialize mit CEF-Code, Ausnahmen mit Art)")


## Quelltext: erstes Öffnen lädt ohne Druck, der Dialog liegt über dem Browser und hat sofort den Fokus.
func _ablauf_quelle() -> void:
	print("Ablauf und Fokus (Quelltext)")
	var b := FileAccess.get_file_as_string("res://src/ui/layers/browser.gd")
	var a := b.find("func _kern_anbieten() -> void:")
	var teil := b.substr(a, b.find("main.open_layer(k)", a) - a)
	check(teil.contains("while is_inside_tree() and not Nav.layers.has(self)"), "Dialog erst, wenn der Browser oben liegt (sonst lag er dahinter, 0.16.15)")
	var ui := FileAccess.get_file_as_string("res://src/ui/layers/browser_kern_ui.gd")
	check(ui.contains("_starten()") and ui.contains("Nav.focus(_first_focus(), true)") and not ui.contains("Nav.focus(null"), "Dialog: lädt ohne extra Druck, Fokus sofort auf dem Knopf, nie fokuslos")
	var bv := FileAccess.get_file_as_string("res://src/ui/sections/browser_view.gd")
	check(bv.contains("KernLauf.automatisch()") and bv.contains("set_meta(\"uz_on_x\"") and bv.contains("\"Abbrechen\""), "Startbühne: lädt beim ersten Öffnen, zeigt den Fortschritt, X bricht ab")
	var kern := FileAccess.get_file_as_string("res://src/core/browser_kern.gd")
	var la := kern.substr(kern.find("static func laden("), kern.find("static func _holen(") - kern.find("static func laden("))
	check(la.contains("HOST + \"index.json\", PackedStringArray(), HTTPClient.METHOD_GET, \"\", 120.0, \"api\", MAX_INDEX, false)")
		and la.contains("await Net.parse_json(ri.body)") and K.MAX_INDEX <= 64 * 1024 * 1024, "index.json: fester Host, ohne Weiterleitung, feste Grenze, im Hintergrund gelesen")
	check(la.contains("url_datei(name + \".sha1\")") and la.contains("4096, false)") and la.find("minimal_aus_index(") < la.find("name + \".sha1\""),
		"Rückfall .sha1-Beilage nur, wenn index.json nichts nennt (gleicher Host, https)")
	check(la.contains("protokoll(diag, LISTE_MAX)"), "Diagnose zum Index ins Protokoll")
	check(la.contains("url_datei(mname), PackedStringArray(), HTTPClient.METHOD_GET, \"\", 30.0, \"api\", MAX_LISTE, false)") and la.contains("manifest_pruefen(")
		and la.contains("_schreiben(spiegel.path_join(mname), rm.body)") and la.find("manifest_pruefen(") < la.find("_holen("),
		"Manifest des Installers: fester Host, ohne Weiterleitung, geprüft vor den großen Downloads, roh in den Spiegel")
	check(la.find("dateien_auslegen()") < la.find("\"kern-auslegen\""), "Stummel und Filter liegen, bevor der Helfer auslegt (0.16.15: „ließ sich nicht auslegen“)")
	var ho := kern.substr(kern.find("static func _holen("), 3000)
	check(la.count(", false)") >= 3 and ho.count(", false)") >= 1 and ho.contains("max_bytes, false, stop)"), "keine Weiterleitungen, Größengrenzen, Abbruch auch im Download")
	check(la.contains("MAX_ARCHIV, \"Archiv\"") and la.contains("MAX_MINIMAL, \"Bootstrap-Archiv\"") and la.find("\"Archiv\", fortschritt") < la.find("\"Bootstrap-Archiv\", fortschritt"),
		"signierte und minimal-Verteilung je mit eigener Grenze")
	check(ho.count("await _geprueft(pfad, sha1, sha256, groesse)") == 2 and ho.contains("DirAccess.remove_absolute(pfad)") and ho.contains("liegt schon geprüft da")
			and kern.contains("return await Arbeit.ergebnis(_pruefsummen_ok.bind(pfad, sha1, sha256, groesse), Arbeit.LANG) == true"),
		"Prüfsummen und Größe (im Hilfsfaden; nur ein echtes „stimmt“ zählt); falsches Archiv wird gelöscht, geprüftes bleibt liegen")
	# Die Prüfung selbst, mit einer echten Datei: richtige und falsche Summen, falsche Größe, fehlende Datei.
	var pd := Config.path("kern_test_archiv.bin")
	var pf := FileAccess.open(pd, FileAccess.WRITE)
	pf.store_buffer("Uzai prüft Archive".to_utf8_buffer())
	pf.close()
	var p1 := "Uzai prüft Archive".sha1_text()
	var p256 := "Uzai prüft Archive".sha256_text()
	var plen := "Uzai prüft Archive".to_utf8_buffer().size()
	check(await K._geprueft(pd, p1, p256, plen) and await K._geprueft(pd, p1, "", -1), "Archiv mit richtigen Prüfsummen: gilt (SHA-256 und Größe nur, wenn bekannt)")
	check(not await K._geprueft(pd, p1, "0".repeat(64), plen) and not await K._geprueft(pd, "0".repeat(40), p256, plen)
			and not await K._geprueft(pd, p1, p256, plen + 1) and not await K._geprueft(pd + ".fehlt", p1, p256, plen),
			"falsche SHA-1, falsche SHA-256, falsche Größe oder keine Datei: gilt nicht")
	DirAccess.remove_absolute(pd)
	check(la.contains("\"boot\": archiv_boot") and la.contains("DirAccess.remove_absolute(archiv_boot)") and la.find("DirAccess.remove_absolute(archiv_boot)") > la.find("\"kern-ressource\""),
		"Bootstrap-Archiv geht an den Helfer und wird erst nach dem Erfolg gelöscht")
	var mn := FileAccess.get_file_as_string("res://src/main.gd")
	check(mn.contains("browser_kern_lauf.gd\").vorab(get_tree())"), "vorab nur mit Zustimmung (browser.kern_vorab)")
	check(not bool(Config.DEFAULTS.browser.kern_vorab), "vorab ist aus voreingestellt")



## Alles, was der Browser zur Laufzeit neben den Helfer legt oder aus res:// liest, muss der Export
## mitnehmen (export_presets.cfg include_filter). In 0.16.17 fehlte uzai-browser-gemeinsam.cs im Paket:
## „Uzais eigene Kern-Dateien fehlen“ – nur unter Windows sichtbar, darum hier geprüft.
func _im_paket() -> void:
	print("Im Windows-Paket")
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	var a := cfg.find("include_filter=\"")
	var filt := cfg.substr(a + 16, cfg.find("\"", a + 16) - a - 16)
	var muster: Array = Array(filt.split(",")).map(func(s: String) -> String: return s.strip_edges())
	var noetig: Array = ["helper/uzai-helper.ps1", "assets/browser/cef/uzai-browser-start.dll",
		"assets/browser/filter/filter.gz", "assets/browser/filter/cookies.json"]
	var wirt := load("res://src/core/browser_wirt.gd")
	for q in wirt.QUELLEN:
		noetig.append("helper/" + str(q))
	for q2 in ["uzai-browser-gemeinsam.cs", "uzai-browser-kern.cs", "uzai-browser-karte.js", "uzai-browser-filter.js"]:
		noetig.append("helper/" + q2)
	var fehlt: Array = []
	for f in noetig:
		if not FileAccess.file_exists("res://" + str(f)):
			fehlt.append(str(f) + " (nicht im Projekt)")
		elif not muster.any(func(m: String) -> bool: return str(f).match(m)):
			fehlt.append(str(f))
	check(fehlt.is_empty(), "alle Laufzeit-Dateien des Browsers im Export %s" % str(fehlt))

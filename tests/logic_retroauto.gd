extends Node
## Retro ohne Einrichtung (Roadmap 19, 104, R5) ohne Bildschirm und ohne Netz: Systemerkennung,
## feste Quellen (Allowlist), Paketnamen nach festem Muster, Prüfung der GitHub-Daten,
## Lizenz-Pflicht, Namen in Archiven (Zip-Slip, Bomben, Verknüpfungen), Liste von tar, Kerne,
## Fassungen, Grundeinstellungen – und dass es nie BIOS-Links und nie Switch-Emulatoren gibt.
## Aufruf: godot --headless --path . res://tests/logic_retroauto.tscn

const RA := preload("res://src/core/retro_auto.gd")
const Paket := preload("res://src/core/paket.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_quellen()
	_katalog()
	_github()
	_erkennen()
	_bios()
	_archive()
	_kerne()
	_fassungen()
	_grund()
	# „Bereit“ nur, wenn der Auftrag sein Ende erreicht hat: Nach einem Abbruch mitten im Lauf kommt beim Warten ""
	# an, und das hieße sonst „kein Fehler“.
	var quelle := FileAccess.get_file_as_string("res://src/core/retro_laden.gd")
	var lauf := quelle.substr(quelle.find("func _lauf("), 1600)
	check(lauf.contains("not bool(a.get(\"ok\", false))") and lauf.find("a.get(\"ok\"") < lauf.find("\"fertig\"")
			and quelle.count("[\"ok\"] = true") == 3, "Einrichten: fertig nur mit eigenem Vermerk am Ende (Emulator, Kern, Vorführung)")
	check(not quelle.contains("func _tar(") and quelle.contains("YouTube.windows_tar()"), "tar nur über die eine Stelle im Systemordner")
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _quellen() -> void:
	print("Feste Quellen")
	check(RA.quelle_ok("https://api.github.com/repos/PCSX2/pcsx2/releases/latest"), "GitHub-API erlaubt")
	check(RA.quelle_ok("https://buildbot.libretro.com/stable/1.22.2/windows/x86_64/RetroArch.7z"), "Buildbot erlaubt")
	check(RA.quelle_ok("https://dl.dolphin-emu.org/releases/2609a/dolphin-2609a-x64.7z"), "Dolphin-Server erlaubt")
	for bad in ["http://github.com/a/b", "https://github.com.evil.example/a", "https://evilgithub.com/a", "https://api.github.com:8443/x",
			"https://user@github.com/a", "https://GITHUB.COM/a", "https://github.com", "ftp://github.com/a", "https://example.com/rom.zip",
			"https://objects.githubusercontent.com/x", "https://github.com/a b", "https://github.com\\@evil.example/", "file:///C:/x.exe"]:
		check(not RA.quelle_ok(bad), "nicht erlaubt: %s" % bad)
	check(
			RA.weiterleitung_ok("https://github.com/PCSX2/pcsx2/releases/download/v1/x.7z",
			"https://release-assets.githubusercontent.com/github-production-release-asset/1?sig=a"), "GitHub → eigener Dateiserver")
	check(RA.weiterleitung_ok("https://github.com/a/b", "https://objects.githubusercontent.com/x"), "GitHub → objects.githubusercontent.com")
	check(not RA.weiterleitung_ok("https://github.com/a/b", "https://evil.example/x")
			and not RA.weiterleitung_ok("https://github.com/a/b", "http://objects.githubusercontent.com/x"), "GitHub → woandershin oder http: nein")
	check(not RA.weiterleitung_ok("https://buildbot.libretro.com/x", "https://objects.githubusercontent.com/x")
			and not RA.weiterleitung_ok("https://dl.dolphin-emu.org/x", "https://dl.dolphin-emu.org/y"), "feste Pakete: keine Weiterleitung")


func _katalog() -> void:
	print("Katalog, Lizenz-Pflicht, keine Switch")
	for id in RA.KATALOG.keys():
		var e: Dictionary = RA.KATALOG[id]
		check(RA.lizenz_ok(str(e.lizenz)), "%s: Lizenztext liegt bei (%s)" % [id, e.lizenz])
		check(not (e.systeme as Array).has("switch"), "%s: nicht für Switch" % id)
		check((e.exe as Array).all(func(x: String) -> bool: return RA.pfad_ok(x) and x.ends_with(".exe") and not x.contains("/")),
				"%s: Programmdatei mit festem Namen" % id)
		if str(e.quelle) == "fest":
			check(RA.quelle_ok(str(e.url)) and str(e.sha256).length() == 64 and str(e.sha256).is_valid_hex_number() and RA.quelle_ok(str(e.neu)),
					"%s: feste Fassung mit Adresse und SHA-256" % id)
			var a := RA.angebot_fest(str(id), 1234)
			check(bool(a.ok) and int(a.groesse) == 1234 and str(a.pruefung).contains("fest"), "%s: Angebot der festen Fassung" % id)
		else:
			check(RA.quelle_ok(RA.GITHUB_API % str(e.repo)) and RegEx.create_from_string("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$").search(str(e.repo)) != null,
					"%s: Repository fest" % id)
			check(str(e.muster).begins_with("^") and str(e.muster).ends_with("$"), "%s: Paketname nach vollem Muster" % id)
	for k in RA.KERN_INFO.keys():
		check(RA.kern_ok(str(k)), "Kern %s: Lizenztext liegt bei" % k)
	check(not RA.lizenz_ok("Snes9x") and not RA.lizenz_ok(""), "ohne Lizenztext: nicht angeboten")
	var ohne: Dictionary = RA.eintrag("ppsspp").duplicate()
	ohne["lizenz"] = "Eigene-Lizenz"
	check(not bool(RA._angebot("ppsspp", ohne, "1", "1", "x.zip", "https://github.com/x", 1, "a".repeat(64), "").ok), "Lizenz-Pflicht greift im Angebot")
	check(RA.NIE.has("switch") and not RA.KERNE.has("switch"), "Switch steht auf der Nie-Liste")
	for id in ["ryubing", "eden", "citron", "sudachi", "yuzu"]:
		check(not RA.KATALOG.has(id), "kein Switch-Emulator im Angebot: %s" % id)
	check(not RA.KERNE.has("arcade") and not RA.KERN_INFO.has("fbneo") and not RA.KERN_INFO.has("snes9x"), "keine Kerne mit nicht freier Lizenz")
	var lic := RA.lizenz("GPL-3.0")
	check(str(lic.text).begins_with("GNU GENERAL PUBLIC LICENSE") and str(lic.text).contains("Version 3"), "GPL-Text vollständig")
	check(str(RA.lizenz("CC-BY-NC-ND-4.0").text).contains("NonCommercial"), "DuckStation: Lizenz CC BY-NC-ND 4.0 ehrlich genannt")


func _release(tag := "v2.8.2", name := "pcsx2-v2.8.2-windows-x64-Qt.7z", repo := "PCSX2/pcsx2", size := 25690112,
		digest := "sha256:" + "ab".repeat(32)) -> Dictionary:
	return { "tag_name": tag, "draft": false, "prerelease": false, "published_at": "2026-10-01T10:00:00Z", "assets": [
		{ "name": "pcsx2-v2.8.2-windows-x64-installer.exe", "size": 44000000, "digest": "sha256:" + "cd".repeat(32),
			"browser_download_url": "https://github.com/PCSX2/pcsx2/releases/download/v2.8.2/pcsx2-v2.8.2-windows-x64-installer.exe" },
		{ "name": name, "size": size, "digest": digest, "browser_download_url": "https://github.com/%s/releases/download/%s/%s" % [repo, tag, name] }] }


func _github() -> void:
	print("Release-Daten von GitHub")
	var a := RA.angebot_github("pcsx2", _release())
	check(bool(a.ok) and str(a.fassung) == "2.8.2" and int(a.groesse) == 25690112 and str(a.sha256) == "ab".repeat(32),
			"gültiges Release: Fassung, Größe, SHA-256 (%s)" % a.get("error", ""))
	check(str(a.datei) == "pcsx2-v2.8.2-windows-x64-Qt.7z" and str(a.archiv) == "7z" and str(a.lizenz) == "GPL-3.0", "nur das portable Paket, nie der Installer")
	check(str(a.url) == "https://github.com/PCSX2/pcsx2/releases/download/v2.8.2/pcsx2-v2.8.2-windows-x64-Qt.7z", "Adresse genau nach GitHub-Muster")
	check(not bool(RA.angebot_github("pcsx2", _release("v2.8.2", "pcsx2-v2.8.2-windows-x64-Qt.7z.exe")).ok), "falscher Paketname: nein")
	check(not bool(RA.angebot_github("pcsx2", _release("v2.8.2", "../pcsx2-v2.8.2-windows-x64-Qt.7z")).ok), "Paketname mit Pfad: nein")
	check(not bool(RA.angebot_github("pcsx2", _release("v2.8.2", "pcsx2-v2.8.2-windows-x64-Qt.7z", "Boese/pcsx2")).ok), "Adresse eines anderen Repositorys: nein")
	check(not bool(RA.angebot_github("pcsx2", _release("v2.8.2/../x")).ok) and not bool(RA.angebot_github("pcsx2", _release("v2.8.2 x")).ok),
			"Tag mit Sonderzeichen: nein")
	check(not bool(RA.angebot_github("pcsx2", _release("v2.8.2", "pcsx2-v2.8.2-windows-x64-Qt.7z", "PCSX2/pcsx2", 900 * 1024 * 1024)).ok), "zu groß: nein")
	check(not bool(RA.angebot_github("pcsx2", _release("v2.8.2", "pcsx2-v2.8.2-windows-x64-Qt.7z", "PCSX2/pcsx2", 1000)).ok), "zu klein: nein")
	var no_sha := RA.angebot_github("pcsx2", _release("v2.8.2", "pcsx2-v2.8.2-windows-x64-Qt.7z", "PCSX2/pcsx2", 25690112, ""))
	check(not bool(no_sha.ok) and str(no_sha.error).contains("Prüfsumme"), "ohne SHA-256 von GitHub: nichts laden")
	check(not bool(RA.angebot_github("pcsx2", _release("v2.8.2", "pcsx2-v2.8.2-windows-x64-Qt.7z", "PCSX2/pcsx2", 25690112, "sha1:abc")).ok), "nur sha256 zählt")
	var pre := _release()
	pre["prerelease"] = true
	check(not bool(RA.angebot_github("pcsx2", pre).ok), "Vorabfassung: nein")
	var twice := _release()
	(twice.assets as Array).append((twice.assets as Array)[1].duplicate())
	check(not bool(RA.angebot_github("pcsx2", twice).ok), "zwei passende Pakete: nein")
	check(not bool(RA.angebot_github("pcsx2", "kein json").ok) and not bool(RA.angebot_github("pcsx2", { "tag_name": "v1", "assets": "x" }).ok),
			"kaputte Daten: nein")
	check(not bool(RA.angebot_github("retroarch", _release()).ok), "feste Fassung nimmt keine GitHub-Pakete")
	var duck := RA.angebot_github("duckstation",
			{ "tag_name": "latest", "published_at": "2026-10-12T08:00:00Z", "assets": [{ "name": "duckstation-windows-x64-release.zip",
		"size": 73295462, "digest": "sha256:" + "0f".repeat(32),
			"browser_download_url": "https://github.com/stenzek/duckstation/releases/download/latest/duckstation-windows-x64-release.zip" }] })
	check(bool(duck.ok) and str(duck.fassung) == "Fassung vom 12.10.2026" and str(duck.kennung) == "0f".repeat(32),
			"laufende Fassung: Datum als Fassung, SHA-256 als Kennung")
	for id in ["ppsspp", "melonds", "duckstation"]:
		var re := RegEx.create_from_string(str(RA.eintrag(id).muster))
		check(re.search("x" + "PPSSPP-v1.20.4-Windows-x64.zip") == null and re.search("melonDS-1.1-windows-x86_64.zip.sig") == null, "%s: Muster verankert" % id)
	check(RegEx.create_from_string(str(RA.eintrag("ppsspp").muster)).search("PPSSPP-v1.20.4-Windows-x64.zip") != null, "PPSSPP: echtes Paket passt")
	check(RegEx.create_from_string(str(RA.eintrag("melonds").muster)).search("melonDS-1.1-windows-x86_64.zip") != null, "melonDS: echtes Paket passt")
	check(RegEx.create_from_string(str(RA.eintrag("ppsspp").muster)).search("PPSSPP-v1.20.4-Windows-ARM64.zip") == null, "PPSSPP: nicht das ARM-Paket")


func _systems() -> Array:
	return [
		{ "id": "ps2", "name": "PlayStation 2", "short": "PS2", "emulator": "pcsx2" },
		{ "id": "ps1", "name": "PlayStation", "short": "PS1", "emulator": "duckstation" },
		{ "id": "gba", "name": "Game Boy Advance", "short": "GBA", "emulator": "mgba" },
		{ "id": "snes", "name": "Super Nintendo", "short": "SNES", "emulator": "retroarch", "core": "snes9x" },
		{ "id": "nes", "name": "NES", "short": "NES", "emulator": "retroarch", "core": "mesen" },
		{ "id": "switch", "name": "Switch", "short": "Switch", "emulator": "ryubing" },
		{ "id": "3ds", "name": "Nintendo 3DS", "short": "3DS", "emulator": "azahar" },
		{ "id": "arcade", "name": "Arcade", "short": "Arcade", "emulator": "retroarch", "core": "fbneo" },
		{ "id": "gc", "name": "GameCube", "short": "GC", "emulator": "dolphin" },
		{ "id": "wii", "name": "Wii", "short": "Wii", "emulator": "dolphin" },
	]


func _erkennen() -> void:
	print("Systeme erkennen")
	var emus := {
		"pcsx2": { "exe": "" }, "duckstation": { "exe": "C:/Emu/DuckStation/duckstation-qt-x64-ReleaseLTCG.exe" },
		"retroarch": { "exe": "", "args": "-L \"{emudir}/cores/{core}_libretro.dll\" \"{rom}\"" }, "mgba": { "exe": "" },
		"ryubing": { "exe": "" }, "azahar": { "exe": "" }, "dolphin": { "exe": "C:/Uzai/emulatoren/dolphin/Dolphin.exe" },
	}
	var da := { "C:/Emu/DuckStation/duckstation-qt-x64-ReleaseLTCG.exe": true }
	var spiele := { "ps2": 12, "ps1": 4, "gba": 7, "snes": 3, "nes": 2, "switch": 5, "3ds": 1, "arcade": 9, "gc": 2, "wii": 0 }
	var l := RA.erkennen(spiele, _systems(), func(id: String) -> Dictionary: return emus.get(id, {}), func(p: String) -> bool: return da.has(p),
		func(_e: Dictionary, _k: String) -> bool: return false, "C:/Uzai/emulatoren")
	var by := {}
	for r in l:
		by[str(r.system)] = r
	check(not by.has("wii"), "System ohne Spiele: nicht gezeigt")
	check(str(l[0].system) == "ps2" and int(l[0].spiele) == 12, "meiste Spiele zuerst")
	check(bool(by.ps1.bereit) and str(by.ps1.angebot) == "", "PS1: eigener Emulator da → bereit")
	check(not bool(by.ps2.bereit) and str(by.ps2.angebot) == "pcsx2", "PS2: PCSX2 fehlt → anbieten")
	check(str(by.gba.angebot) == "retroarch" and str(by.gba.kern) == "mgba", "GBA ohne mGBA-Programm: RetroArch mit Kern mGBA")
	check(str(by.snes.angebot) == "retroarch" and str(by.snes.kern) == "bsnes", "SNES: Kern mit freier Lizenz statt Snes9x")
	check(str(by.nes.kern) == "mesen", "NES: eingestellter freier Kern bleibt")
	check(str(by["switch"].grund) == "switch" and str(by["switch"].angebot) == "", "Switch: nie automatisch")
	check(str(by["3ds"].grund) == "selbst" and str(by.arcade.grund) == "selbst", "3DS und Spielhalle: selbst einrichten")
	check(str(by.gc.angebot) == "dolphin", "GameCube: Dolphin-Datei fehlt → anbieten")
	var p := RA.plan(l)
	check(p.emus == ["pcsx2", "retroarch", "dolphin"] or (p.emus as Array).size() == 3 and (p.emus as Array).has("retroarch"),
			"Plan: drei Emulatoren (%s)" % str(p.emus))
	check((p.kerne as Array).has("mgba") and (p.kerne as Array).has("bsnes") and (p.kerne as Array).has("mesen") and not (p.kerne as Array).has("fbneo"),
			"Plan: nur die freien Kerne")
	check((p.systeme.retroarch as Array).has("gba") and not (p.systeme.get("pcsx2", []) as Array).has("switch"), "Plan: Systeme je Emulator")
	check(RA.fehlt_text(l) == "Für 5 Systeme fehlt ein Emulator", "Satz: %s" % RA.fehlt_text(l))
	check(RA.fehlt_text([]) == "", "nichts fehlt: kein Satz")
	# Eigenes RetroArch ohne Kern: Uzai legt dort nichts hinein.
	var own := { "retroarch": { "exe": "D:/RetroArch/retroarch.exe", "args": "-L \"{emudir}/cores/{core}_libretro.dll\"" } }
	var l2 := RA.erkennen({ "nes": 3 }, [{ "id": "nes", "name": "NES", "emulator": "retroarch", "core": "mesen" }],
			func(id: String) -> Dictionary: return own.get(id, {}),
		func(_p: String) -> bool: return true, func(_e: Dictionary, _k: String) -> bool: return false, "C:/Uzai/emulatoren")
	check(str(l2[0].grund) == "kern_selbst" and str(l2[0].angebot) == "", "eigenes RetroArch ohne Kern: Hinweis statt Download")
	var mine := { "retroarch": { "exe": "C:/Uzai/emulatoren/retroarch/retroarch.exe", "args": "-L \"{emudir}/cores/{core}_libretro.dll\"" } }
	var l3 := RA.erkennen({ "nes": 3 }, [{ "id": "nes", "name": "NES", "emulator": "retroarch", "core": "mesen" }],
			func(id: String) -> Dictionary: return mine.get(id, {}),
		func(_p: String) -> bool: return true, func(_e: Dictionary, _k: String) -> bool: return false, "C:/Uzai/emulatoren")
	check(str(l3[0].angebot) == "retroarch" and str(l3[0].kern) == "mesen", "Uzais RetroArch ohne Kern: Kern anbieten")
	var l4 := RA.erkennen({ "nes": 3 }, [{ "id": "nes", "name": "NES", "emulator": "retroarch", "core": "mesen" }],
			func(id: String) -> Dictionary: return mine.get(id, {}),
		func(_p: String) -> bool: return true, func(_e: Dictionary, _k: String) -> bool: return true, "C:/Uzai/emulatoren")
	check(bool(l4[0].bereit), "mit Kern: bereit")


func _bios() -> void:
	print("BIOS: nur neutraler Hinweis, nie Links")
	var urls := RegEx.create_from_string("(?i)(https?:|www\\.|\\.(com|org|net|io|de|ru|xyz)\\b|://|download|herunterlad)")
	var n := 0
	for sid in ["ps1", "ps2", "saturn", "pce", "dreamcast", "gba", "psp", "gc", "switch"]:
		for id in RA.KATALOG.keys():
			var t := RA.bios_hinweis(sid, "System", str(id), "C:\\Uzai\\emulatoren\\" + str(id))
			if t == "":
				continue
			n += 1
			check(urls.search(t) == null, "%s/%s: keine Adresse, kein Download-Hinweis" % [sid, id])
			check(t.contains("selbst") and t.contains("eigenen") and t.contains("C:\\Uzai\\emulatoren\\"), "%s/%s: selbst sichern, Ordner genannt" % [sid, id])
	check(n == 5, "BIOS-Hinweise für PS1, PS2, Saturn, PC Engine (CD), Dreamcast (%d)" % n)
	check(RA.bios_hinweis("ps2", "PlayStation 2", "pcsx2", "C:\\U\\pcsx2").ends_with("C:\\U\\pcsx2\\bios"), "PS2: Ordner bios im PCSX2-Ordner")
	check(RA.bios_hinweis("gba", "GBA", "retroarch", "C:\\U") == "" and RA.bios_hinweis("switch", "Switch", "retroarch", "C:\\U") == "",
			"GBA und Switch: kein Hinweis")
	# In den Quellen stehen nur Adressen der festen Hosts – nie eine Quelle für BIOS, ROMs, Schlüssel.
	for path in ["res://src/core/retro_auto.gd", "res://src/core/retro_laden.gd", "res://src/ui/layers/retro_einrichten.gd"]:
		var src := FileAccess.get_file_as_string(path)
		var ok := src != ""
		for m in RegEx.create_from_string("https://([a-z0-9.-]+)").search_all(src):
			if not (m.get_string(1) in RA.HOSTS) and not (m.get_string(1) in RA.WEITER["github.com"]):
				ok = false
				print("    fremde Adresse: ", m.get_string())
		check(ok, "%s: nur feste Hosts" % path.get_file())
		check(not RegEx.create_from_string("(?i)(bios|firmware|prod\\.keys|rom)s?[a-z]*\\s*=\\s*\"https").search(src),
				"%s: keine Quellen für BIOS, Firmware, Schlüssel" % path.get_file())


func _zip(entries: Array) -> PackedByteArray:
	return Paket.zip(entries)


func _archive() -> void:
	print("Namen in Archiven, Zip-Slip, Bomben")
	for good in ["retroarch.exe", "RetroArch-Win64/assets/xmb/monochrome/png/x.png", "Qt6Core.dll", "resources/shaders/a b.glsl", "translations/qt_de.qm"]:
		check(RA.pfad_ok(good), "erlaubt: %s" % good)
	for bad in ["../evil.exe", "a/../../b", "/abs/x", "C:/x", "a\\..\\b", "con.txt", "x/NUL", "lpt1.dll", "a.exe:zone", "dir./x", " x", "x ", "a//b", "", "a/./b",
			"x\u0001y", "a?b", "a*.dll"]:
		check(not RA.pfad_ok(bad), "nicht erlaubt: %s" % bad.c_escape())
	var ok := RA.zip_index(_zip([["duckstation-qt-x64-ReleaseLTCG.exe", "MZ".to_ascii_buffer()], ["resources/a.txt", "x".repeat(5000).to_ascii_buffer()]]))
	check(bool(ok.ok) and (ok.entries as Array).size() == 2 and int(ok.total) == 5002, "gültiges Paket gelesen")
	check(not bool(RA.zip_index(_zip([["../evil.txt", "x".to_ascii_buffer()]])).ok), "Zip-Slip „../“: abgelehnt")
	check(not bool(RA.zip_index(_zip([["ok/../../evil.txt", "x".to_ascii_buffer()]])).ok), "Zip-Slip in der Mitte: abgelehnt")
	check(not bool(RA.zip_index(_zip([["C:/Windows/evil.dll", "x".to_ascii_buffer()]])).ok), "Laufwerk im Namen: abgelehnt")
	check(not bool(RA.zip_index(_zip([["a.txt", "x".to_ascii_buffer()], ["A.TXT", "y".to_ascii_buffer()]])).ok), "doppelt in anderer Schreibweise: abgelehnt")
	check(not bool(RA.zip_index(_zip([["a", "x".to_ascii_buffer()], ["a/b.txt", "y".to_ascii_buffer()]])).ok), "Datei und Ordner mit gleichem Namen: abgelehnt")
	# Bombe: das Verzeichnis verspricht riesig entpackt.
	var b := _zip([["big.bin", PackedByteArray([1, 2, 3]).duplicate()]])
	var bomb := _zip([["big.bin", "0".repeat(200000).to_ascii_buffer()]])
	var cd := _cd(bomb)
	bomb.encode_u32(cd + 24, 0x7FFFFFF0)
	var bi := RA.zip_index(bomb)
	check(not bool(bi.ok), "Bombe (Packrate/Größe): abgelehnt (%s)" % bi.get("error", ""))
	# Verknüpfung (Unix-Symlink im Verzeichnis).
	var link := b.duplicate()
	var c2 := _cd(link)
	link.encode_u16(c2 + 4, (3 << 8) | 20)
	link.encode_u32(c2 + 38, 0xA1FF << 16)
	check(not bool(RA.zip_index(link).ok), "Verknüpfung im Paket: abgelehnt")
	var enc := b.duplicate()
	enc.encode_u16(_cd(enc) + 8, 1)
	check(not bool(RA.zip_index(enc).ok), "verschlüsselt: abgelehnt")
	check(not bool(RA.zip_index(PackedByteArray([1, 2, 3])).ok) and not bool(RA.zip_index("kein zip".repeat(10).to_ascii_buffer()).ok), "kein ZIP: abgelehnt")
	var kern := RA.zip_index(_zip([["mgba_libretro.dll", "MZ".to_ascii_buffer()]]), ["mgba_libretro.dll"])
	check(bool(kern.ok), "Kern-Paket mit genau dem Kern")
	check(not bool(RA.zip_index(_zip([["mgba_libretro.dll", "MZ".to_ascii_buffer()], ["autorun.bat", "x".to_ascii_buffer()]]), ["mgba_libretro.dll"]).ok),
			"Kern-Paket mit mehr darin: abgelehnt")

	print("Liste von tar (7z)")
	var lines := "drwxrwxrwx  0 0      0           0 Oct 12 08:01 RetroArch-Win64/\n-rw-rw-rw-  0 0      0     6656512 Oct 12 08:01 RetroArch-Win64/retroarch.exe\n-rw-rw-rw-  0 0      0        1200 Okt  2  2026 RetroArch-Win64/assets/a b.png\n"
	var t := RA.tar_liste(lines)
	check(bool(t.ok) and int(t.files) == 2 and int(t.total) == 6657712, "gültige Liste gelesen (%s)" % t.get("error", ""))
	check(not bool(RA.tar_liste(lines + "lrwxrwxrwx  0 0      0           0 Oct 12 08:01 RetroArch-Win64/x -> C:/Windows\n").ok), "Verknüpfung: abgelehnt")
	check(not bool(RA.tar_liste(lines + "hrw-rw-rw-  0 0      0           0 Oct 12 08:01 RetroArch-Win64/y link to x\n").ok), "harter Link: abgelehnt")
	check(not bool(RA.tar_liste(lines + "-rw-rw-rw-  0 0      0          10 Oct 12 08:01 ../../evil.exe\n").ok), "Zip-Slip in 7z: abgelehnt")
	check(not bool(RA.tar_liste(lines + "-rw-rw-rw-  0 0      0          10 Oct 12 08:01 RetroArch-Win64\\..\\..\\evil.exe\n").ok), "Zip-Slip mit „\\“: abgelehnt")
	check(not bool(RA.tar_liste(lines + "-rw-rw-rw-  0 0      0 99999999999 Oct 12 08:01 RetroArch-Win64/big.bin\n").ok), "entpackt zu groß: abgelehnt")
	check(not bool(RA.tar_liste(lines + "seltsame Zeile\n").ok), "unlesbare Zeile: nichts entpacken")
	check(not bool(RA.tar_liste("").ok), "leer: abgelehnt")


func _cd(z: PackedByteArray) -> int:
	for i in range(z.size() - 22, -1, -1):
		if z.decode_u32(i) == 0x06054b50:
			return z.decode_u32(i + 16)
	return -1


func _kerne() -> void:
	print("Kerne vom Buildbot")
	var idx := "2026-10-20 1a2b3c4d mgba_libretro.dll.zip\n2026-10-20 deadbeef bsnes_libretro.dll.zip\n2026-10-20 zzzzzzzz mesen_libretro.dll.zip\nmüll\n"
	check(RA.kern_crc(idx, "mgba") == 0x1a2b3c4d and RA.kern_crc(idx, "bsnes") == 0xdeadbeef, "CRC32 aus der Liste")
	check(RA.kern_crc(idx, "mesen") == -1 and RA.kern_crc(idx, "stella") == -1, "keine oder kaputte CRC: -1")
	check(RA.kern_url("mgba") == "https://buildbot.libretro.com/nightly/windows/x86_64/latest/mgba_libretro.dll.zip", "Kern-Adresse fest")
	check(RA.kern_url("../x") == "" and RA.kern_url("fbneo") == "" and RA.kern_url("snes9x") == "", "nur erlaubte Kerne")


func _fassungen() -> void:
	print("Fassungen und Updates")
	check(RA.neuer("1.22.2", "1.22.10") and RA.neuer("1.22.2", "1.23") and not RA.neuer("1.22.2", "1.22.2") and not RA.neuer("1.22.2", "1.9.9"),
			"Zahlen als Zahlen")
	check(RA.neuer("2609", "2609a") and RA.neuer("2609a", "2612") and not RA.neuer("2609a", "2606"), "Dolphin-Fassungen")
	check(RA.neue_fassung("retroarch", { "tag_name": "v1.23.0" }) == "1.23.0" and RA.neue_fassung("retroarch", { "tag_name": "v1.22.2" }) == "",
			"RetroArch: neuere Fassung erkannt")
	check(RA.neue_fassung("dolphin", { "shortrev": "2612" }) == "2612" and RA.neue_fassung("dolphin", { "shortrev": "<script>" }) == "",
			"Dolphin: nur Name nach Muster")
	check(RA.neue_fassung("pcsx2", { "tag_name": "v9" }) == "", "GitHub-Emulatoren: Update über das Angebot selbst")
	check(RA.fassung_text("v2.8.2", "") == "2.8.2" and RA.fassung_text("latest", "kaputt") == "Laufende Fassung", "Fassung als Text")


func _grund() -> void:
	print("Grundeinstellungen im eigenen Ordner")
	for id in RA.KATALOG.keys():
		var files := RA.grund_dateien(str(id))
		check(files.keys().all(func(k: String) -> bool: return RA.pfad_ok(k)), "%s: nur Dateien im Ordner des Emulators" % id)
		check(RA.ordner(str(id)).all(func(o: String) -> bool: return RA.pfad_ok(o)), "%s: Ordner im Emulator-Ordner" % id)
	check(str(RA.grund_dateien("retroarch")["retroarch.cfg"]).contains("video_fullscreen = \"true\""), "RetroArch: Vollbild")
	check(str(RA.grund_dateien("dolphin")["User/Config/Dolphin.ini"]).contains("Enabled = False") and RA.grund_dateien("dolphin").has("portable.txt"),
			"Dolphin: tragbar, ohne Nachfrage zur Datensammlung")
	check(str(RA.grund_dateien("pcsx2")["inis/PCSX2.ini"]).contains("Cross = SDL-0/FaceSouth") and RA.grund_dateien("pcsx2").has("portable.ini"),
			"PCSX2: tragbar, Controller belegt")
	check(str(RA.grund_dateien("duckstation")["settings.ini"]).contains("StartFullscreen = true"), "DuckStation: Vollbild")
	var ds := str(RA.grund_dateien("duckstation")["settings.ini"])
	check(ds.contains("Cross = SDL-0/A") and not ds.contains("Face") and not ds.contains("Analog = "),
			"DuckStation: A/B/X/Y (FaceSouth kennt es nicht), kein Analog auf Guide")
	check(not str(RA.grund_dateien("pcsx2")["inis/PCSX2.ini"]).contains("Analog = ") and str(RA.grund_dateien("dolphin")["User/Config/GCPadNew.ini"]).contains("`Motor L`"),
			"PCSX2 ohne Analog auf Guide, Dolphin-Rumble auf Motor L")
	check(RA.ordner("pcsx2") == ["bios"] and RA.ordner("retroarch").has("cores") and RA.ordner("retroarch").has("system"), "Ordner fürs eigene BIOS und die Kerne")

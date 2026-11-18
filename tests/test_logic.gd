extends Node
## Prüft die Logik ohne Oberfläche: VDF-Leser, Steam- und ROM-Suche, Titel, Startparameter,
## ShaderGlass-Profil. Aufruf: godot --headless --path . res://tests/test_logic.tscn

const VDF := preload("res://src/library/vdf.gd")
const RomScanner := preload("res://src/library/rom_scanner.gd")
const SteamScanner := preload("res://src/library/steam_scanner.gd")
const PcScanner := preload("res://src/library/pc_scanner.gd")
const U := preload("res://src/ui/u.gd")

var fails := 0
var root := ""


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _ready() -> void:
	root = OS.get_cache_dir().path_join("uzai-test-%d" % Time.get_ticks_usec())
	print("VDF")
	var v := VDF.parse('"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"C:\\\\Program Files (x86)\\\\Steam"\n\t\t"apps" { "730" "123" }\n\t}\n}\n')
	check(v.has("libraryfolders"), "Wurzel gelesen")
	check(str(v.libraryfolders["0"].path) == "C:\\Program Files (x86)\\Steam", "Pfad mit Backslashes")
	check(str(v.libraryfolders["0"].apps["730"]) == "123", "verschachtelter Block")
	var kante := VDF.parse('// Kopf {\nohne wert\n"leer" ""\n"mit \\"Zitat\\"" "Zeile\\nzwei\\tdrei"\n"offen" "bis zum Ende')
	check(kante.size() == 4 and str(kante.get("ohne", "")) == "wert" and str(kante.get("leer", "x")) == ""
			and str(kante.get('mit "Zitat"', "")) == "Zeile\nzwei\tdrei"
			and str(kante.get("offen", "")) == "bis zum Ende", "Kommentar, Wort ohne Anführungszeichen, leerer Wert, Rückstrich-Folgen, fehlendes Schlusszeichen")
	var vdf_t0 := Time.get_ticks_msec()
	var lang := VDF.parse('"k" "%s"' % "x".repeat(400000))
	check(str(lang.get("k", "")).length() == 400000 and Time.get_ticks_msec() - vdf_t0 < 1000,
			"sehr langer Wert: gelesen, ohne dass Uzai steht (das zeichenweise Lesen brauchte dafür viele Sekunden)")

	print("Steam")
	var steam := root.path_join("Steam")
	var lib2 := root.path_join("SteamLib2")
	write(steam.path_join("steamapps/libraryfolders.vdf"), '"libraryfolders"\n{\n"0" { "path" "%s" }\n"1" { "path" "%s" }\n}\n' % [steam, lib2])
	write(steam.path_join("steamapps/appmanifest_1245620.acf"),
			'"AppState"\n{\n"appid" "1245620"\n"name" "ELDEN RING"\n"installdir" "ELDEN RING"\n"StateFlags" "4"\n"LastPlayed" "1700000000"\n}\n')
	write(steam.path_join("steamapps/appmanifest_228980.acf"), '"AppState" { "appid" "228980" "name" "Steamworks Common Redistributables" "installdir" "x" }')
	write(lib2.path_join("steamapps/appmanifest_367520.acf"), '"AppState" { "appid" "367520" "name" "Hollow Knight" "installdir" "Hollow Knight" }')
	write(lib2.path_join("steamapps/appmanifest_1493710.acf"), '"AppState" { "appid" "1493710" "name" "Proton Experimental" "installdir" "Proton" }')
	check(SteamScanner.find_root("", steam) == steam, "Steam-Ordner erkannt")
	var sg := SteamScanner.scan(steam)
	var names := sg.map(func(g): return g.title)
	check(sg.size() == 2, "zwei Spiele, Werkzeuge ausgelassen (%d)" % sg.size())
	check("ELDEN RING" in names and "Hollow Knight" in names, "beide Bibliotheksordner gelesen")
	check(int(sg.filter(func(g): return g.appid == 1245620)[0].steam_last) == 1700000000, "zuletzt gespielt übernommen")

	print("Alle Steam-Spiele (auch nicht installierte)")
	var lib := [{ "id": "steam:1245620", "title": "ELDEN RING", "source": "steam", "system": "steam", "appid": 1245620, "installed": true },
		{ "id": "steam:570", "title": "Dota 2", "source": "steam", "system": "steam", "appid": 570, "installed": true, "missing": true },
		{ "id": "rom:x", "title": "Zelda", "source": "rom", "system": "n64" }]
	var owned := [{ "appid": 1245620, "name": "ELDEN RING", "playtime_forever": 900 }, { "appid": 570, "name": "Dota 2", "playtime_forever": 30 },
		{ "appid": 367520, "name": "Hollow Knight", "playtime_forever": 60, "rtime_last_played": 1700000000 },
			{ "appid": 228980, "name": "Steamworks Common Redistributables" }]
	var n_un := Library.apply_owned(lib, owned, true, 1)
	var hk: Array = lib.filter(func(g): return str(g.id) == "steam:367520")
	check(n_un == 2 and hk.size() == 1 and not bool(hk[0].installed) and int(hk[0].steam_last) == 1700000000,
			"neu: Hollow Knight als „nicht installiert“, Werkzeuge ausgelassen (%d)" % n_un)
	check(bool(lib[0].installed) and int(lib[0].steam_minutes) == 900, "installiertes Spiel bleibt installiert, Spielzeit von Steam")
	check(not bool(lib[1].installed) and not lib[1].has("missing"), "deinstalliertes Spiel bleibt sichtbar – als „nicht installiert“")
	Library.apply_owned(lib, [], false, 2)
	check(bool(hk[0].get("missing", false)) and bool(lib[1].get("missing", false)) and not lib[0].has("missing") and not lib[2].has("missing"),
			"ausgeschaltet: nur die nicht installierten verschwinden")
	var mo: Array = Library._merge_owned([{ "id": "steam:1245620", "source": "steam", "appid": 1245620, "installed": true }], owned, true)
	check(mo.size() == 3 and int(mo[0].steam_minutes) == 900 and not bool(mo[2].installed),
			"Einlesen: gekaufte Spiele dazu (früher brach das an SteamScanner.is_tool ab – so heißt auch Script.is_tool)")
	var ob := SteamCM.Pb.f_varint(1, 1)
	var og := SteamCM.Pb.f_varint(1, 413150)
	og.append_array(SteamCM.Pb.f_string(2, "Stardew Valley"))
	og.append_array(SteamCM.Pb.f_varint(3, 12))
	og.append_array(SteamCM.Pb.f_varint(4, 5100))
	og.append_array(SteamCM.Pb.f_string(5, "abc"))
	og.append_array(SteamCM.Pb.f_varint(11, 1690000000))
	ob.append_array(SteamCM.Pb.f_msg(2, og))
	ob.append_array(SteamCM.Pb.f_msg(2, SteamCM.Pb.f_string(2, "ohne ID")))
	var po := SteamCM.parse_owned_games(ob)
	check(po.size() == 1 and int(po[0].appid) == 413150 and str(po[0].name) == "Stardew Valley" and int(po[0].playtime_forever) == 5100
			and int(po[0].rtime_last_played) == 1690000000,
		"Player.GetOwnedGames (protobuf) wie die Web-API gelesen")

	print("ROMs")
	var roms := root.path_join("PS1")
	write(roms.path_join("Final Fantasy VII (Europe) (Disc 1).cue"), 'FILE "Final Fantasy VII (Europe) (Disc 1).bin" BINARY\n  TRACK 01 MODE2/2352\n')
	write(roms.path_join("Final Fantasy VII (Europe) (Disc 1).bin"), "x")
	write(roms.path_join("Final Fantasy VII (Europe) (Disc 2).cue"), 'FILE "Final Fantasy VII (Europe) (Disc 2).bin" BINARY\n')
	write(roms.path_join("Final Fantasy VII (Europe) (Disc 2).bin"), "x")
	write(roms.path_join("Unterordner/Legend of Dragoon, The (USA).chd"), "x")
	write(roms.path_join("liesmich.txt"), "x")
	var sys := { "id": "ps1", "extensions": ["cue", "chd", "bin", "m3u"] }
	var rg := RomScanner.scan(sys, roms)
	var rt := rg.map(func(g): return g.title)
	check(rg.size() == 2, "zwei Spiele gefunden (%d): %s" % [rg.size(), str(rt)])
	check("Final Fantasy VII" in rt, "Discs zusammengefasst, Titel bereinigt")
	check("The Legend of Dragoon" in rt, "Unterordner und „, The“ umgestellt")
	var ff: Dictionary = rg.filter(func(g): return g.title == "Final Fantasy VII")[0]
	check((ff.get("discs", []) as Array).size() == 2, "beide Discs gemerkt")
	check(str(ff.path).ends_with(".cue"), ".cue statt .bin")
	check(RomScanner.clean_title("Zelda_no_Densetsu (Japan) [!]") == "Zelda no Densetsu", "Unterstriche und Klammern")
	check(RomScanner.clean_title("SLES-50330 Shadow of the Colossus") == "Shadow of the Colossus", "PS-Seriennummer vorn fällt weg")
	check(RomScanner.clean_title("SLUS_203.12 - Ico (USA)") == "Ico", "Seriennummer mit Strich dahinter fällt weg")
	check(RomScanner.clean_title("Ico - SCES-50760") == "Ico", "Seriennummer hinten fällt weg")
	check(RomScanner.clean_title("SLES-50330") == "SLES-50330", "nur die Nummer: bleibt als Titel")
	check(RomScanner.clean_title("Gran Turismo 4") == "Gran Turismo 4", "normale Titel unverändert")
	var keep_lib: Array = Library.games
	Library.games = [{ "id": "steam:1245620", "title": "Elden Ring", "source": "steam", "system": "steam", "appid": 1245620 },
		{ "id": "pc:x", "title": "Hollow Knight", "source": "pc", "system": "pc" }]
	Library._reindex()
	check(Library.friend_game_title("ELDEN RING", "1245620") == "Elden Ring", "Freund spielt: Titel aus der Bibliothek (über die Steam-ID)")
	check(Library.friend_game_title("HOLLOW KNIGHT") == "Hollow Knight", "Freund spielt: Titel aus der Bibliothek (über den Namen)")
	check(Library.friend_game_title("Hades") == "Hades" and Library.friend_game_title("") == "", "unbekanntes Spiel bleibt, wie Steam es meldet")
	Library.games = keep_lib
	Library._reindex()

	print("Launcher")
	var a := Launcher.split_args('-fullscreen -nogui -batch -- "D:\\Spiele\\PS2\\Ōkami (EU).iso"')
	check(a.size() == 5 and a[4] == "D:\\Spiele\\PS2\\Ōkami (EU).iso", "Startparameter mit Leerzeichen")
	check(Launcher.win_path("C:\\/Program Files (x86)/Steam//steamapps") == "C:\\Program Files (x86)\\Steam\\steamapps",
			"Windows-Pfad: gemischte und doppelte Trenner zusammengefasst")
	check(Launcher.win_path("\\\\nas/spiele") == "\\\\nas\\spiele", "Windows-Pfad: Netzwerkpfad bleibt")
	var sgp := Launcher.sgp_text(Config.filter("crt480"))
	check(sgp.contains('ShaderCategory "crt"') and sgp.contains('ShaderName "crt-guest-advanced-hd"'), "Shader im Profil")
	check(sgp.contains('Param-4-intres "4.5"') and sgp.contains('Param-4-inter "500'), "deine PS2-Werte im Profil")
	check(sgp.contains('PixelSize "1"') and sgp.contains('Clone "1"'), "Pixel Size x1, Fenster klonen")
	check(Config.filter("crt-rgb").get("pixel_size") == "9", "PS1-Vorschlag x9")

	print("Erfolge")
	check(Achievements.norm("Legend of Zelda, The: The Minish Cap") == Achievements.norm("The Legend of Zelda - The Minish Cap"),
			"Titelvergleich für RetroAchievements")

	print("YouTube")
	var rss := """<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
 <title>Kanal &amp; Co</title>
 <entry>
  <id>yt:video:abcdefghijk</id>
  <yt:videoId>abcdefghijk</yt:videoId>
  <yt:channelId>UCxyz</yt:channelId>
  <title>Tom &amp; Jerry &quot;Spezial&quot; &#8211; Teil 2</title>
  <link rel="alternate" href="https://www.youtube.com/watch?v=abcdefghijk"/>
  <author><name>Retro-Werkstatt</name><uri>https://www.youtube.com/channel/UCxyz</uri></author>
  <published>2026-09-30T15:00:12+00:00</published>
  <media:group>
   <media:title>Anderer Titel</media:title>
   <media:thumbnail url="https://i2.ytimg.com/vi/abcdefghijk/hqdefault.jpg" width="480" height="360"/>
   <media:community><media:statistics views="12345"/></media:community>
  </media:group>
 </entry>
 <entry>
  <yt:videoId>shortshort1</yt:videoId>
  <title>Ein Short</title>
  <link rel="alternate" href="https://www.youtube.com/shorts/shortshort1"/>
  <author><name>Retro-Werkstatt</name></author>
 </entry>
</feed>"""
	var items := YouTube.parse_rss(rss.to_utf8_buffer())
	check(items.size() == 2, "RSS: zwei Einträge (%d)" % items.size())
	if items.size() == 2:
		check(items[0].title == "Tom & Jerry \"Spezial\" – Teil 2", "RSS: Titel mit Zeichen-Ersetzungen (%s)" % items[0].title)
		check(items[0].channel == "Retro-Werkstatt" and items[0].channel_id == "UCxyz", "RSS: Kanal")
		check(int(items[0].views) == 12345, "RSS: Aufrufe")
		check(int(items[0].published) == int(Time.get_unix_time_from_datetime_string("2026-09-30T15:00:12")), "RSS: Datum")
		check(items[1].short and not items[0].short, "RSS: Shorts erkannt")
	var yj := '{"_type":"playlist","channel":"Pixelbude","channel_id":"UCpix","entries":[' + \
		'{"id":"aaaaaaaaaaa","title":"Video A","channel":null,"uploader":"Pixelbude","duration":125.0,"view_count":4200,"url":"https://www.youtube.com/watch?v=aaaaaaaaaaa"},' + \
		'{"id":"bbbbbbbbbbb","title":"Kurz","duration":30,"url":"https://www.youtube.com/shorts/bbbbbbbbbbb"},' + \
		'{"id":"UCkanal","title":"Ein Kanal","url":"https://www.youtube.com/channel/UCkanal"},' + \
		'{"id":"ccccccccccc","title":"Ohne Zahlen","duration":null,"view_count":null}]}'
	var yl := YouTube.parse_ytdlp(yj, true)
	check(yl.size() == 2, "yt-dlp: Shorts und Kanäle ausgelassen (%d)" % yl.size())
	if yl.size() == 2:
		check(yl[0].duration == 125 and yl[0].views == 4200 and yl[0].channel == "Pixelbude", "yt-dlp: Länge, Aufrufe, Kanal")
		check(yl[1].duration == 0 and yl[1].channel_id == "UCpix", "yt-dlp: fehlende Werte und Kanal der Liste")
	check(YouTube.parse_ytdlp(yj, false).size() == 3, "yt-dlp: Shorts auf Wunsch dabei")
	check(YouTube.parse_iso_duration("PT1H2M3S") == 3723 and YouTube.parse_iso_duration("PT45S") == 45 and YouTube.parse_iso_duration("P1DT1M") == 86460,
			"ISO-Dauer")
	var segs := YouTube.parse_segments(JSON.parse_string('[{"videoID":"other","segments":[{"segment":[1,2]}]},{"videoID":"abc","segments":[{"segment":[90.5,120],"category":"selfpromo","actionType":"skip"},{"segment":[10,20],"category":"sponsor","actionType":"skip"},{"segment":[5,6],"category":"sponsor","actionType":"mute"}]}]'), "abc")
	check(segs.size() == 2 and segs[0].start == 10.0 and segs[1].category == "selfpromo", "SponsorBlock: nur dieses Video, nur Überspringen, sortiert")
	check(YouTube.time_text(3723) == "1:02:03" and YouTube.time_text(65) == "1:05", "Zeitanzeige")
	check(YouTube.views_text(1234567) == "1,2 Mio. Aufrufe" and YouTube.views_text(4200) == "4.200 Aufrufe" and YouTube.views_text(56000) == "56 Tsd. Aufrufe",
			"Aufrufe als Text (%s / %s / %s)" % [YouTube.views_text(1234567), YouTube.views_text(4200), YouTube.views_text(56000)])
	var QR := load("res://src/core/qr.gd")
	var m: Array = QR.encode("https://www.google.com/device", "M")
	check(m.size() == 29 and (m[0] as PackedByteArray).size() == 29, "QR: Version 3 für die Anmelde-Adresse")
	check(m[0][0] == 1 and m[6][6] == 1 and m[0][7] == 0 and m[7][7] == 0, "QR: Suchmuster an der richtigen Stelle")
	check(QR.encode("x".repeat(1300), "H").is_empty(), "QR: zu lang wird abgelehnt (Version 40, Stufe H fasst 1273 Bytes)")

	print("Lossless Scaling")
	Config.set_value("lossless.auto", "pc")
	check(Lossless._wants_auto({ "source": "steam" }) and not Lossless._wants_auto({ "source": "rom" }), "Automatik bei PC-Spielen")
	check(Lossless._wants_auto({ "source": "rom", "lossless": "an" }) and not Lossless._wants_auto({ "source": "steam", "lossless": "aus" }),
			"Einstellung pro Spiel hat Vorrang")
	Config.set_value("lossless.auto", "emu")
	check(Lossless._wants_auto({ "source": "rom" }) and not Lossless._wants_auto({ "source": "steam" }), "Automatik bei Emulator-Spielen")
	check(Lossless.key_problem({ "ok": true, "result": { "sent": true, "accepted": 6, "expected": 6 } }, "CTRL+ALT+S") == "", "Kürzel gedrückt: kein Fehler")
	check(
			Lossless.key_problem({ "ok": true, "result": { "sent": false, "reason": "nicht vorn", "window": "DuckStation" } }, "CTRL+ALT+S").contains("nicht nach vorn"),
			"Spiel nicht vorn: nicht gedrückt, verständlich gemeldet")
	check(Lossless.key_problem({ "ok": true, "result": { "sent": false, "reason": "unbekannt", "unknown": ["STRGG"] } }, "STRGG+S").contains("STRGG"),
			"unbekannte Taste wird genannt")
	check(
			Lossless.key_problem({ "ok": true, "result": { "sent": true, "foreground_elevated": true, "self_elevated": false } },
			"CTRL+ALT+S").contains("Administrator"), "Spiel mit Adminrechten erkannt")
	Config.set_value("lossless.auto", "aus")
	Config.set_value("lossless.hotkey", "CTRL+ALT+S")
	check(Lossless.key_text("CTRL+ALT+S") == "Strg + Alt + S", "Tastenkürzel als Text")
	# Uzai used to send „C:\\Program Files (x86)\…“, which matched no process path.
	check(Lossless.win_path("C:\\/Program Files (x86)/Steam/steamapps/common/Lossless Scaling") == "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Lossless Scaling", "LS: gemischte/doppelte Trenner vereinheitlicht")
	check(Lossless.win_path("//server/share/LS") == "\\\\server\\share\\LS", "LS: Netzwerkpfad bleibt")
	var ls_admin := { "procs": [{ "pid": 4711, "name": "LosslessScaling", "level": 1, "by": "name", "path": "" }], "windows": [], "self_level": 0, "ms": 40 }
	check(Lossless.running(ls_admin) and Lossless.ls_level(ls_admin) == 1, "LS als Administrator, Pfad unlesbar: läuft trotzdem (nach Name)")
	check(Lossless.state_text(ls_admin).contains("nur im Infobereich") and Lossless.state_text(ls_admin).contains("4711"),
			"LS nur im Infobereich: Protokoll nennt Prozess und Zustand")
	check(Lossless.running({ "procs": { "pid": 1, "name": "LosslessScaling", "level": 0 } }), "LS: einzelner Prozess als Objekt statt Liste")
	check(not Lossless.running({ "procs": [], "windows": [] }) and not Lossless.running({ "error": "Zeitüberschreitung" }), "LS läuft nicht / Abfrage ging nicht")
	check(Lossless.state_text({ "error": "Zeitüberschreitung" }).contains("ging nicht"), "Abfrage-Fehler wird nicht als „läuft nicht“ geschrieben")
	var main_win := { "class": "HwndWrapper[LosslessScaling;;1]", "w": 900, "h": 600, "topmost": false, "full": false }
	var big_main := { "class": "HwndWrapper[LosslessScaling;;1]", "w": 1920, "h": 1080, "topmost": false, "full": true }
	var ovl := { "class": "HwndWrapper[LosslessScaling;;2]", "w": 1920, "h": 1080, "topmost": true, "full": true }
	var ovl_ct := { "class": "X", "w": 1920, "h": 1080, "topmost": false, "full": true, "clickthrough": true }
	check(not Lossless.overlay_in([main_win]) and not Lossless.overlay_in([big_main]) and Lossless.overlay_in([main_win, ovl]) and Lossless.overlay_in([ovl_ct]),
			"LS-Bild: nur Vollbild-Fenster oben/durchklickbar zählt")
	check(Lossless.start_problem({ "ok": true, "result": { "started": false, "elevation": true, "code": 740 } }).contains("Administratorrechte"),
			"LS-Start braucht Admin: klare Meldung, keine UAC")
	check(Lossless.start_problem({ "ok": true, "result": { "started": true, "pid": 9 } }) == "", "LS gestartet: weiter warten")
	check(Lossless.start_problem({ "ok": true, "result": { "started": false, "code": 2 } }).contains("von Hand starten")
			and not Lossless.start_problem({ "ok": true, "result": { "started": false, "code": 2 } }).contains("2"), "LS-Start: was zu tun ist, ohne rohen Windows-Code")
	check(Lossless.start_problem({ "ok": false, "error": "Zeitüberschreitung" }).contains("zu lange"), "LS-Start: Helfer-Fehler als Satz")
	var dd := Lossless.decide(true, true, true, 0, 0, "Strg + Alt + S")
	check(dd.active and dd.err == "" and dd.note == "", "LS an und Bild da: bestätigt")
	dd = Lossless.decide(true, false, false, 0, 0, "Strg + Alt + S")
	check(dd.active and dd.err == "" and dd.note.contains("randlos"), "LS-Bild unbekannt: kein Fehler, neutraler Hinweis")
	dd = Lossless.decide(true, false, true, 1, 0, "Strg + Alt + S")
	check(dd.active and dd.err == "" and dd.note.contains("Administrator"), "LS als Admin, Uzai nicht: Hinweis nennt die Ursache")
	dd = Lossless.decide(true, false, true, 1, 1, "Strg + Alt + S")
	check(not dd.note.contains("als Administrator, Uzai nicht"), "beide als Admin: kein Admin-Hinweis")
	dd = Lossless.decide(false, true, true, 0, 0, "Strg + Alt + S")
	check(dd.active and dd.err.contains("noch an"), "Ausschalten, Bild noch da: bleibt an, Meldung")
	dd = Lossless.decide(false, false, true, 0, 0, "Strg + Alt + S")
	check(not dd.active and dd.err == "", "Ausschalten bestätigt")
	var xml := '<?xml version="1.0" encoding="utf-8"?>\n<Settings xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n  <Hotkey>S</Hotkey>\n  <HotkeyModifierKeys>Alt Control</HotkeyModifierKeys>\n</Settings>'
	check(Lossless.parse_settings_hotkey(xml) == "CTRL+ALT+S", "Settings.xml: Standardkürzel gelesen (%s)" % Lossless.parse_settings_hotkey(xml))
	check(Lossless.parse_settings_hotkey("<Hotkey>F12</Hotkey><HotkeyModifierKeys>Shift</HotkeyModifierKeys>") == "SHIFT+F12", "Settings.xml: Umschalt + F12")
	check(Lossless.parse_settings_hotkey("<Hotkey>D5</Hotkey><HotkeyModifierKeys>Control, Shift</HotkeyModifierKeys>") == "CTRL+SHIFT+5",
			"Settings.xml: Ziffer, Komma-Liste")
	check(Lossless.parse_settings_hotkey("<Hotkey>Home</Hotkey><HotkeyModifierKeys>None</HotkeyModifierKeys>") == "HOME", "Settings.xml: ohne Umschalttasten")
	check(Lossless.parse_settings_hotkey("<Hotkey>S</Hotkey>") == "", "Settings.xml ohne Umschalttasten-Eintrag: Uzai-Einstellung gilt")
	check(Lossless.parse_settings_hotkey("<Hotkey>OemTilde</Hotkey><HotkeyModifierKeys>Alt</HotkeyModifierKeys>") == "",
			"Settings.xml: unbekannte Taste → Uzai-Einstellung")
	check(Lossless.parse_settings_hotkey("kaputt") == "", "Settings.xml kaputt → Uzai-Einstellung")

	print("Ordner")
	check(RomScanner.subdir_of("D:/Spiele/PS2", "D:/Spiele/PS2/RPG/Okami.iso") == "RPG", "Unterordner erkannt")
	check(RomScanner.subdir_of("D:/Spiele/PS2", "D:/Spiele/PS2/Okami.iso") == "", "direkt im Ordner: kein Unterordner")
	check(RomScanner.subdir_of("D:\\Spiele\\PS2", "D:\\Spiele\\PS2\\Rennen\\GT4\\gt4.iso") == "Rennen", "Windows-Pfade, tiefer verschachtelt")
	var keep_games := Library.games
	var keep_folders := Library.folders
	Library.games = [
		{ "id": "ps2:a", "title": "A", "system": "ps2", "source": "rom", "path": "x", "subdir": "RPG" },
		{ "id": "ps2:b", "title": "B", "system": "ps2", "source": "rom", "path": "y", "subdir": "RPG" },
		{ "id": "ps2:c", "title": "C", "system": "ps2", "source": "rom", "path": "z", "subdir": "Einzeln" },
		{ "id": "ps2:d", "title": "D", "system": "ps2", "source": "rom", "path": "w", "folders": ["f_1"] },
	]
	Library.folders = [{ "id": "f_1", "name": "Lieblinge", "system": "ps2" }, { "id": "f_2", "name": "Alle", "system": "" }]
	Library._reindex()
	var ff2 := Library.folders_for("ps2")
	var fnames: Array = ff2.map(func(f): return str(f.name))
	check(fnames.has("Lieblinge") and fnames.has("RPG") and not fnames.has("Einzeln"), "eigene + automatische Ordner, nur ab zwei Spielen (%s)" % str(fnames))
	check(Library.in_folder("auto:ps2:RPG").size() == 2 and Library.in_folder("f_1").size() == 1, "Spiele im Ordner")
	Library.set_in_folder("ps2:a", "f_2", true)
	check(Library.is_in_folder(Library.get_game("ps2:a"), "f_2") and Library.global_folders().size() == 1, "Spiel in Ordner für alle legen")
	Library.collections = ["Alt"]
	Library.games[3]["collections"] = ["Alt"]
	Library._migrate_collections()
	check(Library.folders.any(func(f): return f.name == "Alt") and not Library.games[3].has("collections"), "alte Sammlungen werden zu Ordnern")
	Library.games = keep_games
	Library.folders = keep_folders
	Library._reindex()

	print("PC-Spiele")
	var pcdir := root.path_join("PC")
	write(pcdir.path_join("Witcher 3 - Verknüpfung.lnk"), "x")
	write(pcdir.path_join("Diablo IV.url"), "[InternetShortcut]\nURL=battlenet://Fen\n")
	write(pcdir.path_join("Portal.url"), "[InternetShortcut]\nURL=steam://rungameid/400\n")
	write(pcdir.path_join("Webseite.url"), "[InternetShortcut]\nURL=https://example.org\n")
	write(pcdir.path_join("Celeste.exe"), "x")
	write(pcdir.path_join("unins000.exe"), "x")
	write(pcdir.path_join("Unterordner/Hades.lnk"), "x")
	var pcs := PcScanner.scan([pcdir])
	var pt: Array = pcs.map(func(g): return str(g.title))
	check(pcs.size() == 4, "4 Spiele: Verknüpfungen, .url, .exe (%s)" % str(pt))
	check(pt.has("Witcher 3") and pt.has("Hades") and pt.has("Celeste") and pt.has("Diablo IV"), "Namen ohne „- Verknüpfung“")
	check(pcs.filter(func(g): return g.title == "Diablo IV")[0].url == "battlenet://Fen", "Battle.net-Link übernommen, Steam und Webseiten ausgelassen")
	# Eine .url in einem entpackten Spielordner: nur Starter von Spiele-Läden, nie Dateien, Freigaben oder ms-Protokolle.
	var boese := root.path_join("PC2")
	write(boese.path_join("Datei.url"), "[InternetShortcut]\nURL=file:///C:/Windows/System32/cmd.exe\n")
	write(boese.path_join("Freigabe.url"), "[InternetShortcut]\nURL=\\\\203.0.113.5\\x\\spiel.exe\n")
	write(boese.path_join("Hilfe.url"), "[InternetShortcut]\nURL=ms-msdt:/id PCWDiagnostic\n")
	write(boese.path_join("Parameter.url"), "[InternetShortcut]\nURL=steam://run/400//-console\n")
	check(PcScanner.scan([boese]).is_empty(), "file://, Freigabe, ms-Protokoll, Steam mit Parametern: kein Spiel")
	check(PcScanner.url_ok("goggalaxy://openGameView/1207658924") and PcScanner.url_ok("steam://rungameid/400")
			and not PcScanner.url_ok("search-ms:query=x") and not PcScanner.url_ok("steam://run/400//-x"), "Erlaubnisliste der Starter")
	check(PcScanner.url_ok("steam://rungameid/12345678901234567890"), "Steam-Verknüpfung eines Nicht-Steam-Spiels (64-Bit-Nummer)")
	check(Launcher.lnk_ziel_gesperrt("C:\\Windows\\System32\\cmd.exe") and Launcher.lnk_ziel_gesperrt("C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")
			and not Launcher.lnk_ziel_gesperrt("C:/Windows/explorer.exe") and not Launcher.lnk_ziel_gesperrt("C:/Java/bin/javaw.exe")
			and not Launcher.lnk_ziel_gesperrt(""), ".lnk: Kommandozeilen gesperrt, Store-Spiele (explorer) und Java-Spiele nicht")

	print("Steam-Bilder")
	var st_root := root.path_join("Steam2")
	write(st_root.path_join("steamapps/libraryfolders.vdf"), '"libraryfolders" { }')
	write(st_root.path_join("appcache/librarycache/1245620/2f6c1a/library_600x900.jpg"), "x")
	write(st_root.path_join("appcache/librarycache/367520/library_hero.jpg"), "x")
	write(st_root.path_join("userdata/123/config/grid/367520p.png"), "x")
	var keep_root := Library._steam_root
	Library._steam_root = st_root
	Media._grid_dirs = []
	check(Media._steam_local("1245620", "cover").ends_with("2f6c1a/library_600x900.jpg"), "neuer Steam-Cache mit Unterordner")
	check(Media._steam_local("367520", "hero").ends_with("367520/library_hero.jpg"), "Steam-Cache, alte Struktur")
	check(Media._steam_local("367520", "cover").ends_with("grid/367520p.png"), "eigenes Steam-Artwork hat Vorrang")
	Library._steam_root = keep_root
	Media._grid_dirs = []
	var assets := { "asset_url_format": "steam/apps/1245620/${FILENAME}?t=1", "library_capsule": "ab12/library_600x900.jpg", "header": "header.jpg" }
	check(Media.asset_url_from(assets, "cover", "1245620") == "https://shared.steamstatic.com/store_item_assets/steam/apps/1245620/ab12/library_600x900.jpg?t=1",
			"Store-Adresse mit Prüfsummen-Pfad")
	check(Media.asset_url_from({}, "cover", "1") == "", "ohne Daten keine Adresse")

	print("Emulatoren")
	var line := Launcher.fill_args('-f -g "{rom}" --title "{title}" -d "{rom_dir}" {rom_name}', "D:/Roms/Switch/Zelda TotK.nsp", "", "C:/Emu/eden.exe", "Zelda")
	check(line.contains("Zelda TotK.nsp") and line.contains("--title \"Zelda\"") and line.ends_with("Zelda TotK"),
			"Platzhalter {rom} {title} {rom_dir} {rom_name}")
	var boes := Launcher.fill_args('--title "{title}" -d "{rom_dir}"', "D:/Spiel.iso", "", "C:/Emu/x.exe", 'X" --exec "calc')
	check(boes.count("\"") == 4 and not boes.contains("--exec \""), "Titel mit Anführungszeichen schleust keine Parameter ein")
	if OS.get_name() == "Windows":
		check(boes.ends_with("-d \"D:\\\\\""), "Laufwerksstamm: Rückstrich verdoppelt, das Anführungszeichen bleibt eins (%s)" % boes)
	var nid := Config.add_emulator("Mein Eden", "eden")
	var ne := Config.emulator(nid)
	check(ne.get("custom", false) and ne.get("args", "") == '-f -g "{rom}"' and (ne.systems as Array).has("switch"), "eigener Emulator als Kopie einer Vorlage")
	Config.set_system("switch", "emulator", nid)
	Config.delete_emulator(nid)
	check(Config.emulator(nid).is_empty() and str(Config.system("switch").get("emulator", "")) == "", "Löschen setzt das System zurück")
	Config.set_system("switch", "emulator", "ryubing")
	check(Config.emulators_for("switch").size() >= 5, "mehrere Switch-Emulatoren zur Auswahl (%d)" % Config.emulators_for("switch").size())

	print("Freunde")
	check(Social.join_url({ "id": "7656", "game_id": "730", "lobby": "1097", "server": "" }) == "steam://joinlobby/730/1097/7656", "Beitreten über Lobby")
	check(Social.join_url({ "id": "7656", "game_id": "730", "lobby": "", "server": "1.2.3.4:27015" }) == "steam://connect/1.2.3.4:27015", "Beitreten über Server")
	check(Social.join_url({ "id": "7656", "game_id": "730", "lobby": "", "server": "" }) == "", "kein Beitreten, wenn das Spiel es nicht anbietet")
	check(Remote._page("T", "<p>x</p>").contains("width:100%"), "Handy-Seite wird richtig zusammengesetzt")

	print("Spielzeit")
	var PT = load("res://src/ui/sections/playtime_page.gd")
	check(PT.dur(30) == "< 1 Min." and PT.dur(45 * 60) == "45 Min.", "kurze Zeiten in Minuten")
	check(PT.dur(2 * 3600 + 5 * 60) == "2 Std. 5 Min." and PT.dur(3 * 3600) == "3 Std.", "Stunden mit Minuten (%s)" % PT.dur(2 * 3600 + 5 * 60))
	check(PT.dur(1284 * 3600 + 120) == "1.284 Std.", "große Zahlen mit Punkt (%s)" % PT.dur(1284 * 3600 + 120))
	var WC = load("res://src/ui/components/week_chart.gd")
	check(WC._short(int(4.3 * 3600)) == "4,3 Std.", "Komma nur in der Zahl (%s)" % WC._short(int(4.3 * 3600)))
	var UU = load("res://src/ui/u.gd")
	check(UU.playtime(int(2.5 * 3600)) == "2,5 Std. gespielt", "Spielzeit-Text ohne falsches Komma (%s)" % UU.playtime(int(2.5 * 3600)))

	print("Aussehen und Discord")
	var red := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	red.fill(Color(0.1, 0.1, 0.1))
	red.fill_rect(Rect2i(0, 0, 32, 20), Color(0.85, 0.15, 0.12))
	var vc: Variant = Media.vivid_color(red)
	check(vc is Color and (vc as Color).h < 0.08, "kräftigste Farbe aus einem Bild (%s)" % str(vc))
	var grey := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	grey.fill(Color(0.5, 0.5, 0.5))
	check(Media.vivid_color(grey) == null, "graues Bild hat keine Spielfarbe")
	# Bild mit falscher Endung (PNG als .jpg) und kaputte Datei
	var wrong := Config.path("cache/falsche_endung.jpg")
	red.save_png(wrong)
	var wi := Media.load_image(wrong)
	check(wi != null and wi.get_width() == 32, "PNG mit Endung .jpg lädt trotzdem")
	var broken := Config.path("cache/kaputt.png")
	var bfile := FileAccess.open(broken, FileAccess.WRITE)
	bfile.store_string("kein Bild")
	bfile.close()
	check(Media.load_image(broken) == null, "kaputte Datei ergibt kein Bild")
	var tex_c := ImageTexture.create_from_image(red)
	tex_c.set_meta("uz_vivid", [Color(0.9, 0.1, 0.1)])
	check(Media.color_of(tex_c) == Color(0.9, 0.1, 0.1), "Farbe kommt aus der Textur, ohne Rücklesen")
	var small := Media.soft_image(red, 8)
	check(small != null and small.get_width() <= 16, "weiche Fassung ist klein (%d px)" % (small.get_width() if small else -1))
	var BG = load("res://src/ui/components/background.gd")
	var gr: Color = BG.ground_from(Color(0.2, 0.4, 0.95))
	check(gr.v < 0.2 and absf(gr.h - Color(0.2, 0.4, 0.95).h) < 0.02, "Raumfarbe ist dunkel und behält den Farbton")
	check(Social.channel_url("1", "9") == "discord://-/channels/1/9", "Link zum Sprachkanal")
	var holder := Control.new()
	var lab := Label.new()
	lab.add_theme_color_override("font_color", Color.WHITE)
	holder.add_child(lab)
	# Helle Auswahl (Themes ohne Rahmen-Cursor): die Schrift wird dunkel und wieder hell.
	var keep_matt: bool = UzTheme._cursor_matt
	UzTheme._cursor_matt = false
	UU.etikett(holder, true)
	var dark_ok := lab.get_theme_color("font_color") == UzTheme.col("on_focus")
	UU.etikett(holder, false)
	check(dark_ok and lab.get_theme_color("font_color") == Color.WHITE, "Etikett färbt Schrift dunkel und wieder zurück")
	# Rahmen-Cursor (Marke): die Schrift bleibt, wie sie ist – wie im Guide.
	UzTheme._cursor_matt = true
	UU.etikett(holder, true)
	var same_ok := lab.get_theme_color("font_color") == Color.WHITE
	UU.etikett(holder, false)
	check(same_ok and lab.get_theme_color("font_color") == Color.WHITE, "Cursor der Marke: Schrift bleibt hell, nichts springt")
	UzTheme._cursor_matt = keep_matt
	holder.free()
	check(UzTheme.text_on(Color(UzTheme.PRESETS.uzai.focus)).get_luminance() < 0.2, "Schrift auf der hellen Auswahl ist dunkel")
	check(UzTheme.text_on(Color("#7b7e87")).get_luminance() < 0.2, "Schrift auf mittlerem Grau (Ersatz-Hülle PS1) ist dunkel")
	check(UzTheme.text_on(Color("#4b6dff")).get_luminance() > 0.8 and UzTheme.text_on(Color("#e5484d")).get_luminance() > 0.8,
			"Schrift auf sattem Blau (Tiefsee) und auf Warnrot bleibt hell")
	check(UzTheme.radius == 10 and UzTheme.r_panel() == 14 and UzTheme.r_cover() == 12 and UzTheme.strict(),
			"Graphit (Marke): weich gerundet – Zeilen 10, Karten 14, Cover 12 px")
	var missing := Sfx.NAMES.filter(func(n): return not Sfx._streams.has(n))
	check(missing.is_empty(), "alle Menüklänge geladen (%s)" % ", ".join(PackedStringArray(missing)))
	var BGa = load("res://src/ui/components/background.gd")
	var aur: Array = BGa.aurora_from(Color(0.2, 0.4, 0.95))
	check(aur.size() == 3 and (aur[0] as Color).v > 0.6 and absf((aur[0] as Color).h - Color(0.2, 0.4, 0.95).h) < 0.02, "Farbverläufe aus der Spielfarbe")
	check((BGa.aurora_from(Color(0.5, 0.5, 0.5))[0] as Color).s > 0.2, "graues Cover: Verläufe in warmem Gold")

	print("Discord-Sprachkanal (RPC)")
	var sent: Array = []
	var keep_transport: Callable = Voice.transport
	Voice.transport = func(j: String) -> void: sent.append(JSON.parse_string(j))
	Voice.demo = false
	Voice.state = "verbinde"
	Voice.me_id = ""
	Voice.members = []
	Voice.channel = {}
	Config.set_value("accounts.discord_token", "tok")
	Config.set_value("accounts.discord_expires", int(Time.get_unix_time_from_system()) + 3600)
	Voice.handle({ "cmd": "DISPATCH", "evt": "READY", "data": { "v": 1 } })
	check(not sent.is_empty() and sent.back().cmd == "AUTHENTICATE" and sent.back().args.access_token == "tok", "gespeicherter Zugang wird benutzt")
	sent.clear()
	Voice.handle({ "cmd": "AUTHENTICATE", "data": { "user": { "id": "4", "username": "ich" } } })
	var cmds := sent.map(func(x): return str(x.cmd) + ":" + str(x.get("evt", "")))
	check(Voice.state == "bereit" and Voice.me_id == "4", "angemeldet, eigene ID bekannt")
	check("SUBSCRIBE:VOICE_CHANNEL_SELECT" in cmds and "GET_SELECTED_VOICE_CHANNEL:" in cmds, "Kanalwechsel abonniert, aktueller Kanal abgefragt")
	sent.clear()
	Voice.handle({ "cmd": "GET_SELECTED_VOICE_CHANNEL", "data": { "id": "9", "name": "Zocken", "guild_id": "1", "voice_states": [
		{ "nick": "", "user": { "id": "1", "username": "pixelpaul", "avatar": "abc" }, "voice_state": { "self_mute": false }, "volume": 100, "mute": false },
		{ "user": { "id": "4", "username": "ich" }, "voice_state": { "self_mute": true }, "volume": 100, "mute": false },
		{ "nick": "Mira", "user": { "id": "3", "username": "mira_x" }, "voice_state": { "self_mute": true }, "volume": 50, "mute": true } ] } })
	check(Voice.members.size() == 3 and Voice.members[0].me, "drei Leute im Kanal, du stehst vorn")
	check(Voice.member("1").avatar == "https://cdn.discordapp.com/avatars/1/abc.png?size=128", "Profilbild aus Discord")
	check(Voice.member("3").name == "Mira" and Voice.member("3").volume == 50 and Voice.member("3").local_mute,
			"Spitzname, Lautstärke und „für mich stumm“ übernommen")
	var subs := sent.filter(func(x): return x.cmd == "SUBSCRIBE").map(func(x): return str(x.evt))
	check("SPEAKING_START" in subs and "VOICE_STATE_UPDATE" in subs and sent.any(func(x): return x.cmd == "GET_CHANNELS"),
			"Sprechen und Änderungen im Kanal abonniert, andere Kanäle abgefragt")
	Voice.handle({ "cmd": "DISPATCH", "evt": "SPEAKING_START", "data": { "user_id": "1", "channel_id": "9" } })
	check(Voice.member("1").speaking and Voice.speaking_count() == 1, "wer spricht, wird markiert")
	Voice.handle({ "cmd": "DISPATCH", "evt": "SPEAKING_STOP", "data": { "user_id": "1" } })
	check(not Voice.member("1").speaking, "hört auf zu sprechen")
	sent.clear()
	Voice.set_volume("1", 250)
	check(sent.back().cmd == "SET_USER_VOICE_SETTINGS" and int(sent.back().args.volume) == 200 and Voice.member("1").volume == 200,
			"Lautstärke für eine Person, höchstens 200 %")
	Voice.set_local_mute("1", true)
	check(sent.back().args.mute == true and Voice.member("1").local_mute, "für mich stumm")
	Voice.set_self_mute(false)
	check(sent.back().cmd == "SET_VOICE_SETTINGS" and sent.back().args.mute == false and not Voice.member("4").self_mute, "eigenes Mikro schalten")
	Voice.set_self_deaf(true)
	check(sent.back().args.deaf == true and Voice.self_deaf, "eigenen Ton schalten")
	Voice.join("11")
	check(sent.back().cmd == "SELECT_VOICE_CHANNEL" and sent.back().args.channel_id == "11", "Kanal wechseln")
	Voice.leave()
	check(sent.back().cmd == "SELECT_VOICE_CHANNEL" and sent.back().args.channel_id == null, "Kanal verlassen")
	sent.clear()
	Voice.handle(
			{ "cmd": "GET_CHANNELS",
			"data": { "channels": [{ "id": "9", "name": "Zocken", "type": 2 }, { "id": "10", "name": "allgemein", "type": 0 },
			{ "id": "11", "name": "Speedrun-Ecke", "type": 2 }] } })
	check(Voice.others.size() == 1 and Voice.others[0].name == "Speedrun-Ecke" and sent.back().cmd == "GET_CHANNEL", "andere Sprachkanäle ohne Textkanäle")
	Voice.handle({ "cmd": "GET_CHANNEL", "data": { "id": "11", "voice_states": [{ "user": { "id": "21", "username": "kai" } }] } })
	check(Voice.others[0].members.size() == 1 and Voice.others[0].members[0].name == "kai", "wer in den anderen Kanälen ist")
	Voice.handle({ "cmd": "DISPATCH", "evt": "VOICE_STATE_DELETE", "data": { "user": { "id": "3" } } })
	check(Voice.members.size() == 2 and Voice.member("3").is_empty(), "wer geht, verschwindet")
	# Die Kanal-Listen stammen noch aus der Zeit im Kanal: Du stehst in „Zocken“ als Mitglied.
	Voice.browse_guild = "1"
	Voice.browse = [{ "id": "9", "name": "Zocken", "members": [{ "id": "1", "name": "pixelpaul", "avatar": "" }, { "id": "4", "name": "ich", "avatar": "" }] }]
	sent.clear()
	Voice.handle({ "cmd": "DISPATCH", "evt": "VOICE_CHANNEL_SELECT", "data": { "channel_id": null } })
	check(Voice.channel.is_empty() and Voice.members.is_empty() and sent.any(func(x): return x.cmd == "UNSUBSCRIBE"), "Kanal verlassen: Liste leer, Abos beendet")
	check(Voice.browse[0].members.size() == 1 and str(Voice.browse[0].members[0].id) == "1", "nach dem Verlassen stehst du in keiner Kanal-Liste mehr")
	check(sent.any(func(x): return x.cmd == "GET_CHANNELS" and str(x.args.guild_id) == "1"), "und die Kanäle des Servers werden frisch geholt")
	Voice.handle(
			{ "cmd": "GET_CHANNELS", "data": { "channels": [{ "id": "9", "name": "Zocken", "type": 2 }, { "id": "11", "name": "Speedrun-Ecke", "type": 2 }] } })
	check(Voice.others.size() == 2 and Voice.others[0].name == "Zocken" and Voice.others_guild == "1", "der verlassene Kanal steht wieder bei den anderen")
	check(Voice.browse.size() == 2 and Voice.browse[0].members.size() == 1, "die Kanäle zur Wahl behalten ihre Leute, bis die Antwort da ist")
	Voice.handle(
			{ "cmd": "GET_CHANNEL",
			"data": { "id": "9", "voice_states": [{ "user": { "id": "1", "username": "pixelpaul" } }, { "user": { "id": "4", "username": "ich" } }] } })
	check(Voice.others[0].members.size() == 1 and Voice.browse[0].members.size() == 1 and str(Voice.others[0].members[0].id) == "1",
			"nennt Discord dich kurz danach noch im alten Kanal, zählst du nicht mit")
	check(Voice.listen_ids([{ "id": "9" }, { "id": "11" }], [{ "id": "11" }, { "id": "12" }, "kaputt"]) == ["9", "11", "12"], "Kanäle beider Listen, jeder einmal")
	var liste := [{ "id": "9", "members": [{ "id": "4" }, { "id": "1" }, "kaputt"] }, "kaputt", { "id": "11" }]
	Voice.ohne_person(liste, "4")
	check((liste[0].members as Array).size() == 2 and str(liste[0].members[0].id) == "1", "eine Person aus einer Liste nehmen, Fremdes bleibt stehen")
	Voice.browse_guild = ""
	Voice.browse = []
	Voice.handle({ "cmd": "AUTHORIZE", "evt": "ERROR", "data": { "code": 5000, "message": "OAuth2 Error: access_denied" } })
	check(Voice.state == "getrennt" and Voice.error == "In Discord abgelehnt.", "abgelehnte Freigabe wird erklärt")
	# Vor der Veröffentlichung: Mit Uzais eigener Discord-App kommen nur eingetragene Tester durch – das steht dann da.
	check(Voice.freigabe_fehler(4002, "Invalid scope", true) == Voice.TESTER_TEXT and Voice.TESTER_TEXT.contains("eigenen Discord-App")
			and Voice.freigabe_fehler(4002, "Invalid scope", false) == "Discord: Invalid scope" and Voice.freigabe_fehler(0, "", false) == "Freigabe hat nicht geklappt."
			and Voice.freigabe_fehler(5000, "x", true) == "In Discord abgelehnt.", "Freigabe scheitert mit Uzais App: ohne Fachwörter, mit dem Weg zur eigenen App")
	# Neue Nutzer mit Uzais App sehen gleich den Weg zur eigenen App; wer Uzais App schon nutzen konnte, verbindet direkt.
	var VoiceS = load("res://src/core/voice.gd")
	check(VoiceS.direkt_ok(false, false, "") and VoiceS.direkt_ok(true, true, "") and VoiceS.direkt_ok(true, false, "r")
			and not VoiceS.direkt_ok(true, false, ""), "Uzais App direkt nur mit Merker oder Zugang, eigene App immer")
	var DC = load("res://src/ui/layers/discord_connect.gd")
	check(DC.nur_eigene(false, false) and not DC.nur_eigene(true, false) and not DC.nur_eigene(false, true)
			and DC.EIGENE_TEXT.contains("eigene Discord-App") and DC.EIGENE_TEXT.contains("3 Minuten"), "Discord verbinden: neue Nutzer gleich zur eigenen App")
	var vsrc := FileAccess.get_file_as_string("res://src/core/voice.gd")
	var sksrc := FileAccess.get_file_as_string("res://src/ui/sections/settings_konten.gd")
	check(vsrc.contains("Config.set_value(\"accounts.discord_uzai_app\", true)") and sksrc.contains("l.uzai_app = true")
			and sksrc.contains("set_meta(\"uz_on_hold_a\""), "Merker nach dem ersten Zugang mit Uzais App; langes A als Weg für Freigeschaltete")
	check(Voice.app_id_ok("123456789012345678") and Voice.app_id_ok("12345678901234567") and not Voice.app_id_ok("1234")
			and not Voice.app_id_ok("12345678901234567890123") and not Voice.app_id_ok("12345678901234567a") and not Voice.app_id_ok(""),
			"eigene App-ID: 17 bis 20 Ziffern")
	Config.set_value("accounts.discord_client_id", "123456789012345678")
	Config.set_value("accounts.discord_client_secret", "abcdefghijklmnopqrstuvwxyz012345")
	Voice.transport = func(j: String) -> void: sent.append(JSON.parse_string(j))
	# Wie in Uzai: Die neue App-ID trennt (aus), dann verbinden ohne Freigabe (getrennt).
	Voice.state = "verbinde"
	Voice.state = "getrennt"
	sent.clear()
	Voice.authorize()
	check(Voice.state == "anmelden" and Voice.step == "freigabe" and not sent.is_empty() and sent.back().cmd == "AUTHORIZE",
			"Freigabe anfordern: Schritt „in Discord bestätigen“")
	check(Voice.REDIRECTS[0] == "http://localhost", "Code-Tausch zuerst mit der empfohlenen Adresse (ein Code gilt nur einmal)")
	# Lehnt die Discord-App den Zugang zweimal ab, endet es mit einem Hinweis statt im Kreis.
	Config.set_value("accounts.discord_refresh", "")
	Voice.state = "anmelden"
	Voice.step = "tausch"
	Voice.step = "anmelden"
	Voice.handle({ "cmd": "AUTHENTICATE", "evt": "ERROR", "data": { "code": 4009, "message": "Invalid token" } })
	check(Voice.state == "getrennt" and Voice.error.contains("nicht angenommen") and Voice.error.contains("Invalid token"),
			"abgelehnte Anmeldung: Grund von Discord sichtbar")
	check(Voice.explain_token_error("HTTP 403").contains("blockiert"), "Sperre von discord.com wird erklärt")
	Voice.step = "fertig"
	Config.set_value("accounts.discord_client_id", "")
	Config.set_value("accounts.discord_client_secret", "")
	check(Voice.status_text({ "id": "1", "name": "x", "speaking": true }) == "spricht" and Voice.status_text({ "id": "2", "self_mute": true }) == "Mikro aus",
			"Zustand unter dem Namen")
	Voice.transport = keep_transport
	Voice.state = "aus"
	Config.set_value("accounts.discord_token", "")
	Config.set_value("accounts.discord_expires", 0)
	# Unechter Bot-Token, erst zur Laufzeit zusammengesetzt: Als ganzer Text hielte GitHubs Schutz vor Geheimnissen ihn für
	# einen echten Discord-Token und nähme den Push nicht an.
	var bot_attrappe := ".".join(PackedStringArray(["MTIz" + "A".repeat(20), "G" + "b".repeat(5), "c".repeat(27)]))
	check(Voice.check_ids("123456789012345678", bot_attrappe).contains("Bot-Token"),
			"Bot-Token im Secret-Feld wird erkannt")
	check(Voice.check_ids("Uzai", "abcdefghijklmnopqrstuvwxyz012345").contains("Ziffern"), "App-ID muss eine Zahl sein")
	check(Voice.check_ids("123456789012345678", "abcdefghijklmnopqrstuvwxyz012345") == "", "richtige Angaben gehen durch")
	var aus := Voice.log_form({ "cmd": "AUTHENTICATE", "data": { "access_token": "geheim", "channel_id": "123456789012345678" } })
	check(not aus.contains("geheim") and not aus.contains("123456789012345678") and aus.contains("access_token"),
			"Protokoll ohne Zugangsdaten und Kennungen, nur Feldnamen")
	# Was Discord schickt, steht nur der Form nach im Protokoll: keine Nachrichten, Namen und Server anderer Leute.
	var lf := Voice.log_form({ "cmd": "DISPATCH", "evt": "NOTIFICATION_CREATE", "data": { "channel_id": "1", "title": "Mira",
		"body": "streng geheim", "message": { "content": "streng geheim", "author": { "username": "mira" } } } })
	check(lf.begins_with("DISPATCH NOTIFICATION_CREATE") and lf.contains("message") and not lf.contains("geheim") and not lf.to_lower().contains("mira"),
			"Protokoll ohne Inhalt fremder Nachrichten: " + lf)
	check(Voice.log_form({ "cmd": "AUTHORIZE", "evt": "ERROR", "data": { "code": 5000, "message": "OAuth2 Error: access_denied" } }).contains("5000")
			and Voice.log_form({ "cmd": "GET_GUILDS", "evt": null, "data": { "guilds": [{ "name": "Retro-Runde" }] } }) == "GET_GUILDS {guilds}"
			and Voice.log_form({ "cmd": "X" }) == "X", "Protokoll: Fehler mit Code und Text, sonst nur die Namen der Felder")
	check(Voice.explain_token_error("invalid_client: x").contains("Client-Secret")
			and Voice.explain_token_error("invalid_request: Invalid redirect_uri").contains("Redirects"), "Fehler von Discord werden erklärt")

	print("Bibliothek und Cover")
	var lg := { "appid": 570.0, "last_played": 1700000000.0, "title": "Dota 2" }
	Library.fix_numbers(lg)
	check(str(lg.appid) == "570" and lg.last_played is int, "Steam-ID nach dem Laden wieder eine ganze Zahl")
	var urls: PackedStringArray = Media.libretro_urls({ "system": "ps2", "path": "C:/roms/ps2/Ratchet & Clank (Europe).iso", "title": "Ratchet & Clank" })
	check(urls.size() == 2 and urls[0] == "https://thumbnails.libretro.com/Sony%20-%20PlayStation%202/Named_Boxarts/Ratchet%20_%20Clank%20%28Europe%29.png",
			"Libretro-Cover aus dem Dateinamen")

	print("YouTube: Für dich")
	var nowt := 1_700_000_000
	var hist := [{ "id": "seen1", "channel_id": "UCa", "done": true }, { "id": "x2", "channel_id": "UCa", "pos": 5 }]
	var cands := [
		{ "id": "seen1", "channel_id": "UCa", "published": nowt - 3600, "views": 1000 },
		{ "id": "a1", "channel_id": "UCa", "published": nowt - 3600, "views": 50000 },
		{ "id": "b1", "channel_id": "UCb", "published": nowt - 86400 * 40, "views": 100 },
		{ "id": "s1", "channel_id": "UCc", "published": nowt, "short": true },
	]
	var mix: Array = YouTube.rank_mix(cands, hist, [], [], nowt, 1)
	check(mix.size() == 2 and mix[0].id == "a1", "Für dich: Gesehenes und Shorts raus, Lieblingskanal vorn")
	check(YouTube.explain_cookie_error("ERROR: Could not copy Chrome cookie database").contains("Firefox"), "Cookie-Fehler wird erklärt")

	print("Musik")
	var tr := Music.track_from(
			{ "uri": "spotify:track:1", "id": "1", "name": "Song", "duration_ms": 200000, "artists": [{ "name": "A" }, { "name": "B" }],
			"album": { "name": "Al", "images": [{ "url": "big" }, { "url": "mid" }, { "url": "small" }] } })
	check(tr.title == "Song" and tr.artist == "A, B" and tr.art == "mid" and tr.art_big == "big", "Spotify-Titel mit Interpreten und Bild")
	check(
			Music.tracks_from_items([{ "track": { "uri": "spotify:track:2", "name": "X" } }, { "track": null },
			{ "track": { "uri": "spotify:episode:3", "type": "episode" } }]).size() == 1, "Playlist-Einträge: nur Titel")

	print("Steam-Chat")
	var cm := SteamChat.parse_messages(
			{ "response": { "messages": [{ "accountid": 5, "timestamp": 20, "message": "hi [emoticon]steamhappy[/emoticon]" },
			{ "accountid": 9, "timestamp": 10, "message": "hallo" }] } }, 5)
	check(cm.size() == 2 and cm[0].text == "hallo" and not cm[0].me and cm[1].me and cm[1].text == "hi :steamhappy:",
			"Verlauf sortiert, eigene erkannt, Emoticons lesbar")
	check(SteamChat.account_id("76561197960265733") == 5, "Steam-ID zu Konto-ID")
	var jwt := "x." + Marshalls.utf8_to_base64('{"sub":"76561198000000001","exp":99}').replace("+", "-").replace("/", "_").trim_suffix("=").trim_suffix("=") + ".y"
	check(str(SteamChat.jwt_claims(jwt).get("sub", "")) == "76561198000000001", "Steam-Zugang: Steam-ID aus dem Token")
	check(SteamChat.send_result({ "code": 200, "headers": PackedStringArray(["Content-Type: application/json", "x-eresult: 1"]) }) == "1",
			"Senden: Steam nimmt an")
	check(SteamChat.send_result({ "code": 200, "headers": PackedStringArray(["X-eresult: 84"]) }) == "84", "Senden: Ablehnung trotz HTTP 200 erkannt")
	check(SteamChat.send_result({ "code": 200, "headers": PackedStringArray() }) == "1" and SteamChat.send_result({ "code": 0 }) == "",
			"Senden: ohne Kopf zählt der HTTP-Code")
	check(SteamChat.send_error(200, "84").contains("bremst") and SteamChat.send_error(400, "400").contains("nicht angenommen")
			and not SteamChat.send_error(400, "400").contains("400"), "Senden: Grund statt nur „nicht angenommen“")
	var nd := Net._decode(
			{ "ok": false, "code": 403, "body": "Check settings on developer.spotify.com/dashboard, the user may not be registered.".to_utf8_buffer() })
	check(nd.data == null and str(nd.text).contains("not be registered"), "Antwort ohne JSON: Text bleibt erhalten")
	var nr := { "ok": false, "code": 403, "data": null, "text": str(nd.text) }
	Music._text_as_error(nr)
	check(Music.classify(403, nr.data) == "nutzer", "Spotify-Ablehnung als reiner Text erkannt")
	check(Music.classify(403, { "error": { "status": 403, "message": "Active premium subscription required for the owner of the app" } }) == "premium",
			"Premium-Sperre erkannt")

	print("Discord-Musikstatus")
	var MP := load("res://src/core/music_presence.gd")
	var act: Dictionary = MP.activity(
			{ "title": "To Zanarkand", "artist": "Nobuo Uematsu", "album": "FFX", "duration": 186000, "playing": true, "uri": "spotify:track:abc",
			"art": "https://i.scdn.co/image/x" }, 60000, 1000000)
	check(int(act.type) == 2 and int(act.start) == 999940 and int(act.end) == 999940 + 186, "„Hört …“ mit Restzeit")
	check((act.buttons as Array).size() == 1 and str(act.buttons[0].url) == "https://open.spotify.com/track/abc" and str(act.image).begins_with("https://"),
			"Knopf zum Mithören und Cover")
	check(MP.activity({ "title": "X", "playing": false }, 0, 1).is_empty(), "Pause: kein Status")

	print("Songtext")
	var LY := load("res://src/core/lyrics.gd")
	var ly: Dictionary = LY.parse("[00:12.50] Erste Zeile\n[01:02.00] Zweite\nKaputt", "")
	check(str(ly.state) == "ok" and (ly.synced as Array).size() == 2 and int(ly.synced[0][0]) == 12500 and int(ly.synced[1][0]) == 62000,
			"LRC-Zeilen mit Zeit gelesen")
	check(LY.line_at(ly.synced, 5000) == -1 and LY.line_at(ly.synced, 13000) == 0 and LY.line_at(ly.synced, 70000) == 1, "laufende Zeile gefunden")
	check(str(LY.parse("", "").state) == "keine", "ohne Text: keine")

	print("Shop-Bilder")
	var au: Array = Store.art_urls({ "appid": 620, "capsule": "c.jpg", "header": "h.jpg" })
	check(au.size() == 4 and str(au[0]).ends_with("/620/library_600x900_2x.jpg") and str(au[2]) == "c.jpg", "Hochformat: Hülle 2× zuerst, dann Kapsel")
	check(Store.art_urls({ "appid": 620, "capsule": "c.jpg" }, false) == ["c.jpg"], "Quer (Erweiterungen): Kapsel")

	print("Shop")
	var its := Store.parse_items(
			[{ "id": 10, "name": "A", "final_price": 999, "original_price": 1999, "discount_percent": 50 }, { "id": 10, "name": "A" },
			{ "id": 11, "type": 1, "name": "Paket" }])
	check(its.size() == 1 and its[0].header.contains("/10/header.jpg"), "Shop: doppelte und Pakete raus, Bild auch ohne Angabe")
	check(Store.review_label(980, 1000) == "Äußerst positiv" and Store.review_label(50, 100) == "Ausgeglichen", "Bewertungen wie bei Steam")
	var srt := Store.sorted([{ "appid": 1, "name": "b", "price": 500, "discount": 10 }, { "appid": 2, "name": "a", "price": 100, "discount": 70 }], "preis",
			{ 1: true })
	check(srt.size() == 1 and srt[0].appid == 2, "Sortieren und Gekauftes ausblenden")
	var det := Store.parse_details(
			{ "short_description": "Kurz &amp; gut", "supported_languages": "Englisch, Deutsch<strong>*</strong>", "genres": [{ "description": "Action" }],
			"release_date": { "date": "1. Jan. 2025", "coming_soon": false } })
	check(det.about == "Kurz & gut" and det.my_lang and det.genres[0] == "Action", "Spieleseite: Text, Sprache, Genre")

	print("0.6")
	check(Music.app_name("SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify") == "Spotify" and Music.app_name("Chrome") == "Chrome",
			"Musik-App aus der Windows-Kennung")
	var BGb = load("res://src/ui/components/background.gd")
	var bp: Vector2 = BGb.blur_params(4.0)
	check(bp.x <= 2.2 and bp.y > 0.03 and BGb.blur_params(0.0) == Vector2.ZERO, "Weichzeichner: mittlere Mipmap-Stufe plus Spirale statt grober Stufe")
	check(U.fade_texture(true) != null and U.rounded_mat(12.0) != null, "Verläufe und runde Bildecken")

	print("Bilder für Emulator-Spiele")
	var RM = load("res://src/core/retro_match.gd")
	var listing := '<a href="../">../</a><a href="Ratchet%20_%20Clank%20%28Europe%29%20%28v1.00%29.png">x</a><a href="Ratchet%20_%20Clank%20%28USA%29%20%28Demo%201%29.png">x</a><a href="Kingdom%20Hearts%20%28Germany%29.png">x</a><a href="Kingdom%20Hearts%20%28USA%29.png">x</a><a href="Kingdom%20Hearts%20II%20%28Europe%29.png">x</a><a href="Legend%20of%20Spyro%2C%20The%20-%20A%20New%20Beginning%20%28Europe%29.png">x</a><a href="Sly%20Cooper%20and%20the%20Thievius%20Raccoonus%20%28USA%29.png">x</a><a href="Sly%20Cooper%20-%20Jeonseolui%20%28Korea%29.png">x</a>'
	var lnames: PackedStringArray = RM.parse_listing(listing)
	check(lnames.size() == 8 and lnames[2] == "Kingdom Hearts (Germany)", "Libretro-Verzeichnis lesen")
	check(RM.parse_listing('{"tree":[{"path":"A (USA).png"},{"path":"readme.md"}]}') == PackedStringArray(["A (USA)"]), "GitHub-Spiegel lesen")
	check(RM.best_name(PackedStringArray(["Kingdom Hearts"]), lnames) == "Kingdom Hearts (Germany)", "gleicher Titel: deutsche Fassung zuerst")
	check(RM.best_name(PackedStringArray(["ratchet_and_clank [PAL]"]), lnames) == "Ratchet _ Clank (Europe) (v1.00)", "Schreibweise egal, keine Demo")
	check(RM.best_name(PackedStringArray(["The Legend of Spyro A New Beginning"]), lnames).begins_with("Legend of Spyro, The"), "„, The“ hinten wird erkannt")
	check(RM.best_name(PackedStringArray(["Sly Cooper"]), lnames) == "Sly Cooper and the Thievius Raccoonus (USA)", "fehlender Untertitel, bessere Region")
	check(RM.best_name(PackedStringArray(["Okami"]), lnames) == "", "nichts Falsches, wenn nichts passt")
	check(RM.wiki_pick([{ "title": "Kingdom Hearts II" }, { "title": "Kingdom Hearts (video game)" }], "Kingdom Hearts") == "Kingdom Hearts (video game)",
			"Wikipedia: richtige Seite")
	check(RM.wiki_pick([{ "title": "PlayStation 2" }], "Okami") == "", "Wikipedia: keine fremde Seite")
	var wf: PackedStringArray = RM.wiki_shots(
			[{ "title": "File:Kingdom Hearts cover.jpg" }, { "title": "File:KH gameplay screenshot.png" }, { "title": "File:Commons-logo.svg" }])
	check(wf == PackedStringArray(["File:KH gameplay screenshot.png"]), "Wikipedia: nur Spielszenen, kein Cover")
	var ri: Array = Achievements._ra_images({ "ImageIngame": "/Images/012345.png", "ImageTitle": null })
	check(ri == ["https://media.retroachievements.org/Images/012345.png"], "RetroAchievements: Spielszene")
	check(Media.libretro_candidates({ "path": "D:/ps2/Okami.iso", "title": "Ōkami" }) == PackedStringArray(["Okami", "Ōkami"]), "Namen aus Datei und Titel")

	print("Steuerung")
	check(Nav.stick_dir(Vector2(0.3, 0.2), 0.5, "") == "", "Stick unter der Schwelle bewegt nichts")
	check(Nav.stick_dir(Vector2(0.7, 0.6), 0.5, "") == "right" and Nav.stick_dir(Vector2(0.2, -0.9), 0.5, "") == "up", "nur die Hauptrichtung zählt")
	check(Nav.stick_dir(Vector2(0.45, 0.5), 0.5, "right") == "right", "gehaltene Richtung springt nicht bei leicht schrägem Stick")
	check(Nav.repeat_ms(0) > Nav.repeat_ms(12) and Nav.repeat_ms(0) >= 140, "Halten beginnt ruhig und wird dann etwas schneller")
	# Eingespeiste Pause-Taste ohne Extended-Kennzeichen: Windows meldet die Scan-Nummer von G.
	var fired: Array = []
	var on_cmd := func(c: String) -> void: fired.append(c)
	Nav.command.connect(on_cmd)
	var mk := InputEventKey.new()
	mk.keycode = KEY_MEDIAPLAY
	mk.physical_keycode = KEY_G
	mk.pressed = true
	Nav._input(mk)
	var gk := InputEventKey.new()
	gk.keycode = KEY_G
	gk.physical_keycode = KEY_G
	gk.pressed = true
	Nav._input(gk)
	check(not fired.is_empty() and fired.count("guide") == 1, "Pause/Play öffnet nie den Guide (nur das echte G): " + str(fired))
	# Im Spiel (ohne Fensterfokus) kommt vom Controller nur noch der Weg zurück an – auch von
	# PlayStation- und Nintendo-Pads, die der Helfer (nur XInput) nicht sieht.
	fired.clear()
	var keep_pt := Nav.passthrough
	Nav.passthrough = true
	var pad := func(btn: JoyButton, down: bool) -> InputEventJoypadButton:
		var e := InputEventJoypadButton.new()
		e.device = 0
		e.button_index = btn
		e.pressed = down
		return e
	Nav._input(pad.call(JOY_BUTTON_A, true))
	Nav._input(pad.call(JOY_BUTTON_START, true))
	check(fired.is_empty(), "ohne Fokus lösen A und Start nichts aus: " + str(fired))
	Nav._input(pad.call(JOY_BUTTON_GUIDE, true))
	Nav._input(pad.call(JOY_BUTTON_GUIDE, false))
	check(fired == ["guide"], "ohne Fokus öffnet die Guide-Taste den Guide: " + str(fired))
	fired.clear()
	Input.parse_input_event(pad.call(JOY_BUTTON_BACK, true))
	Input.flush_buffered_events()
	Nav._input(pad.call(JOY_BUTTON_START, true))
	Input.parse_input_event(pad.call(JOY_BUTTON_BACK, false))
	Input.flush_buffered_events()
	check(fired == ["guide"], "ohne Fokus öffnet View + Start den Guide: " + str(fired))
	Nav.passthrough = keep_pt
	Nav.command.disconnect(on_cmd)

	print("Speichern: Sicherung und Wiederherstellung")
	var jf := Config.path("test_sicherung.json")
	Config.write_json(jf, { "n": 1 })
	Config.write_json(jf, { "n": 2 })
	check(int(Config.read_json(jf, {}).get("n", 0)) == 2 and FileAccess.file_exists(jf + ".bak"), "neue Fassung, die alte liegt als .bak daneben")
	var bf := FileAccess.open(jf, FileAccess.WRITE)
	bf.store_string("{\"n\": 3, \"abgeschnit")
	bf.close()
	check(int(Config.read_json(jf, {}).get("n", 0)) == 1, "abgeschnittene Datei: letzte gute Fassung statt leer")
	# Volle Platte: Das Schreiben bricht mittendrin ab. write_json zählt nach, bevor es die gute Fassung ersetzt.
	var uf := Config.path("test_umlaute.json")
	check(Config.write_json(uf, { "größe": "Übermaß – 日本語" }) and str(Config.read_json(uf, {}).get("größe", "")) == "Übermaß – 日本語",
			"Umlaute und andere Schriften: geschrieben, nachgezählt (in Bytes), gelesen")
	var soll := FileAccess.get_file_as_bytes(uf).size()
	check(Config.ganz_geschrieben(uf, soll) and not Config.ganz_geschrieben(uf, soll + 1) and not Config.ganz_geschrieben(uf + ".gibtsnicht", 0),
			"nachzählen: stimmt nur bei genau der Länge, und nur wenn es die Datei gibt")
	var hf := FileAccess.open(uf, FileAccess.WRITE)
	hf.store_buffer(FileAccess.get_file_as_bytes(jf + ".bak").slice(0, 3))
	hf.close()
	check(not Config.ganz_geschrieben(uf, soll), "halb geschriebene Datei fällt auf")
	DirAccess.remove_absolute(jf)
	check(int(Config.read_json(jf, {}).get("n", 0)) == 1, "fehlende Datei (Absturz beim Umbenennen): Sicherung")
	DirAccess.remove_absolute(jf + ".bak")
	check(Config.read_json(jf, { "leer": true }).has("leer"), "ganz ohne Datei: Standard")
	var st := { "theme": { "hidden_sections": "videos", "dim": "hell", "font": 5 }, "library": { "sort": "title" } }
	Config.sanitize(st, { "theme": { "hidden_sections": [], "dim": 0.4, "font": "hanken" }, "library": { "sort": "recent" } })
	check(st.theme.hidden_sections == [] and is_equal_approx(float(st.theme.dim), 0.4) and st.theme.font == "hanken",
			"falsche Typen in den Einstellungen: Standard")
	check(st.library.sort == "title", "richtige Werte bleiben")

	print("Rückrufe nach dem Schließen (Release-Absturz)")
	var cb_log: Array = []
	var gone := CbProbe.new()
	var guarded_gone := Media.guard(gone.make_cb(cb_log))
	gone.free()
	guarded_gone.call(null)
	check(cb_log.is_empty(), "Rückruf eines geschlossenen Knotens wird nie aufgerufen")
	var alive := CbProbe.new()
	Media.guard(alive.make_cb(cb_log)).call(null)
	check(cb_log.size() == 1 and alive.hits == 1, "Rückruf eines lebenden Knotens kommt an")
	alive.free()
	check(Media.guard(Callable()).is_null(), "leerer Rückruf bleibt leer")

	print("Videos: mpv vorn mit Uzais Leiste")
	check(Video.front_mode(), "Standard: Video vorn (kein durchsichtiges Fenster mehr)")
	var keep_disp: Variant = Config.get_value("youtube.display", "mpv")
	Config.set_value("youtube.display", "overlay")
	check(not Video.front_mode(), "„Uzai darüber“ bleibt wählbar")
	Config.set_value("youtube.display", keep_disp)
	var dir := Video.prepare_osd()
	check(FileAccess.file_exists(dir.path_join("uzai_osd.lua")) and FileAccess.file_exists(dir.path_join("fonts/UzaiSans-Bold.ttf"))
			and FileAccess.file_exists(dir.path_join("fonts/OFL.txt")), "Skript, Schrift und Lizenz liegen für mpv bereit")
	var lua := FileAccess.get_file_as_string(dir.path_join("uzai_osd.lua"))
	check(lua.contains("register_script_message(\"meta\"") and lua.contains("Uzai Sans Bold"), "Leiste versteht Uzais Nachrichten")
	Video.video = { "id": "v1", "title": "Titel", "channel": "Kanal", "views": 512000, "published": int(Time.get_unix_time_from_system()) - 90000 }
	Video.queue = [Video.video, { "id": "v2", "title": "Danach" }]
	Video.index = 0
	Video.segments = [{ "start": 10.0, "end": 20.0, "category": "sponsor" }]
	var om := Video.meta_for_osd()
	check(str(om.title) == "Titel" and str(om.next) == "Danach" and (om.segments as Array).size() == 1 and str(om.accent).length() == 6,
			"Daten für die Leiste: Titel, Als Nächstes, Abschnitte, Farbe")
	check((om.hints as Array).size() == 8 and (om.hints as Array).any(func(h): return h[0] == "ud" and h[1] == "Lautstärke")
			and (om.hints as Array).any(func(h): return h[1] == "Bild in Bild") and str(om.info).contains("Aufrufe"),
			"Tastenhinweise (mit ↕ Lautstärke und ≡ Bild in Bild) und Aufrufe")
	Video.video = {}
	Video.queue = []
	Video.segments = []

	print("")
	print("Steam-Anmeldung behalten")
	var SC := load("res://src/core/steam_chat.gd")
	var now := 1800000000
	var tok := "x." + Marshalls.utf8_to_base64(JSON.stringify({ "exp": now + 86400, "aud": ["client"] })).replace("+", "-").replace("/", "_").replace("=",
			"") + ".y"
	var old := "x." + Marshalls.utf8_to_base64(JSON.stringify({ "exp": now - 10, "aud": ["client"] })).replace("+", "-").replace("/", "_").replace("=", "") + ".y"
	check(not SC.should_logout(tok, true, false, true, now), "Steam-App: Web-Übergabe abgelehnt → angemeldet bleiben")
	check(not SC.should_logout(tok, false, true, true, now), "Steam-App: Erneuern des Web-Zugangs verweigert (EResult 15) → angemeldet bleiben")
	check(SC.should_logout(tok, true, false, false, now), "Browser-Anmeldung: Web-Übergabe abgelehnt → abmelden")
	check(not SC.should_logout(tok, false, false, false, now), "Aussetzer ohne Ablehnung → angemeldet bleiben")
	check(SC.should_logout(old, false, false, true, now), "abgelaufen → abmelden")
	print("Steam-Chat über die Chat-Server (Protobuf)")
	var CMs := load("res://src/core/steam_cm.gd")
	var Pb = CMs.Pb
	var m1 := PackedByteArray()
	m1.append_array(Pb.f_varint(1, 42))
	m1.append_array(Pb.f_varint(2, 1700000000))
	m1.append_array(Pb.f_string(3, "Hallo [emoticon]steamhappy[/emoticon]"))
	m1.append_array(Pb.f_varint(4, 3))
	var body: PackedByteArray = Pb.f_msg(1, m1)
	var data: Dictionary = SC.messages_from_pb(body)
	var msgs: Array = SC.parse_messages(data, 42)
	check(msgs.size() == 1 and bool(msgs[0].me) and str(msgs[0].text) == "Hallo :steamhappy:" and int(msgs[0].at) == 1700000000,
			"Verlauf aus GetRecentMessages gelesen")
	var sess := PackedByteArray()
	sess.append_array(Pb.f_varint(1, 99))
	sess.append_array(Pb.f_varint(4, 2))
	var sess0 := PackedByteArray()
	sess0.append_array(Pb.f_varint(1, 98))
	sess0.append_array(Pb.f_varint(4, 0))
	var u: Dictionary = SC.unread_from_pb(Pb.f_msg(1, sess) + Pb.f_msg(1, sess0))
	check(u.size() == 1 and int(u.get(str(99 + 76561197960265728), 0)) == 2, "Ungelesenes aus GetActiveMessageSessions gelesen")

	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Knoten mit einer Lambda, die self benutzt (Mitglied hits) – wie Spielseite, Guide-Zeile usw.
class CbProbe extends Node:
	var hits := 0

	func make_cb(log: Array) -> Callable:
		return func(_v: Variant) -> void:
			hits += 1
			log.append(1)

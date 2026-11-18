extends Node
## Eigene Apps (src/core/apps_extern.gd, docs/PLAN_APPS.md Phase 1/2) ohne Windows: Prüfung der
## App-Kennung (AUMID), gesperrte Programme und Pfade, Startparameter, Namen, Speichern im Profil,
## Reihenfolge und Ausblenden in der Reihe, Bestätigung (erster Start, nach einer Sicherung), Liste
## der Store-Apps vom Helfer, Katalog, Logo, und dass Uzai und Helfer dieselbe Sperrliste haben.
## Aufruf: godot --headless --path . res://tests/logic_apps.tscn

const A := preload("res://src/core/apps_extern.gd")
const LeisteOben := preload("res://src/core/leiste_oben.gd")
const Q := preload("res://src/ui/sections/quellen_ordnung.gd")
const Backup := preload("res://src/core/backup.gd")
const HelperScript := preload("res://src/core/helper.gd")
const LauncherScript := preload("res://src/core/launcher.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_pruefungen()
	_speichern()
	var est := _bestaetigung()
	_start_und_liste(est)
	Config.set_value(A.KEY, [])
	print("")
	print("Ergebnis: ", "alles ok" if fails == 0 else "%d Fehler" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _pruefungen() -> void:
	print("App-Kennung (AUMID)")
	for ok in ["4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App", "Disney.37853FC22B2CE_6rarf9sa4v8jt!App",
			"AmazonVideo.PrimeVideo_pwbj9vvecjh7j!App", "Microsoft.ZuneVideo_8wekyb3d8bbwe!Microsoft.ZuneVideo"]:
		check(A.valid_aumid(ok), "gültig: " + ok)
	var bad := ["", "Netflix", "4DF9E0F8.Netflix_mcm4njqhnhss8", "4DF9E0F8.Netflix_mcm4njqhnhss8!", "4DF9E0F8.Netflix_MCM4NJQHNHSS8!App",
		"4DF9E0F8.Netflix_mcm4njqhnhss!App", "4DF9E0F8.Netflix_mcm4njqhnhss8!1App", "4DF9E0F8.Netflix_mcm4njqhnhss8!App..x",
		"4DF9E0F8.Netflix_mcm4njqhnhss8!App\n", "4DF9E0F8.Netflix_mcm4njqhnhss8!App; calc", "4DF9E0F8.Netflix_mcm4njqhnhss8!App&x",
		"..\\..\\x_mcm4njqhnhss8!App", "Ne tflix_mcm4njqhnhss8!App", "ab_mcm4njqhnhss8!App", "4DF9E0F8.Netflix_mcm4njqhnhss8!" + "A".repeat(65),
		"Nétflix.App_mcm4njqhnhss8!App", "x!y!z", "shell:AppsFolder\\4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App"]
	var wrong: Array = bad.filter(func(s: String) -> bool: return A.valid_aumid(s))
	check(wrong.is_empty(), "%d ungültige Kennungen abgelehnt%s" % [bad.size(), ("" if wrong.is_empty() else ": " + str(wrong))])
	check(not A.valid_aumid(42) and not A.valid_aumid(null) and not A.valid_aumid(["x"]), "kein Text: abgelehnt")
	var sp := A.split_aumid("4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App")
	check(sp.family == "4DF9E0F8.Netflix_mcm4njqhnhss8" and sp.name == "4DF9E0F8.Netflix" and sp.app == "Netflix.App", "Paket, Familie und App-Kennung getrennt")
	check(A.split_aumid("x").is_empty(), "ungültig: nichts getrennt")

	print("Programme und Pfade")
	for ok in ["C:\\Program Files\\Kodi\\kodi.exe", "D:/Spiele/Moonlight/Moonlight.exe", "C:\\Program Files\\Plex\\Plex HTPC\\Plex HTPC.exe",
			"C:\\Program Files (x86)\\Steam Link\\SteamLink.exe", "E:\\Tools\\a.EXE"]:
		check(A.path_problem(ok) == "", "in Ordnung: " + ok)
	var blocked := ["C:\\Windows\\System32\\cmd.exe", "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
		"C:\\Program Files\\PowerShell\\7\\pwsh.exe", "C:\\Windows\\System32\\wscript.exe", "C:\\Windows\\System32\\CScript.EXE",
		"C:\\Windows\\System32\\mshta.exe", "C:\\Windows\\System32\\rundll32.exe", "C:\\Windows\\System32\\regsvr32.exe",
		"C:\\Python312\\python3.12.exe", "C:\\Windows\\explorer.exe", "C:\\Windows\\System32\\wsl.exe", "C:\\x\\pwsh7.exe",
		"C:\\Users\\Uz\\AppData\\Local\\Microsoft\\WindowsApps\\wt.exe", "C:\\Windows\\System32\\msiexec.exe"]
	for b in blocked:
		check(A.path_problem(b) == "Shells und Skript-Programme startet Uzai nicht.", "gesperrt: " + b.get_file())
	for b in ["C:\\x\\start.bat", "C:\\x\\start.cmd", "C:\\x\\a.ps1", "C:\\x\\a.vbs", "C:\\x\\a.js", "C:\\x\\a.lnk", "C:\\x\\a.url", "C:\\x\\a.hta",
			"C:\\x\\a.scr", "C:\\x\\a.com", "C:\\x\\a.msi", "C:\\x\\a.exe.lnk", "C:\\x\\kodi"]:
		check(A.path_problem(b) == "Nur Programme (.exe) – keine Skripte oder Verknüpfungen.", "nur .exe: " + b.get_file())
	var weird := ["", "kodi.exe", "\\\\server\\share\\kodi.exe", "\\\\?\\C:\\kodi.exe", "C:kodi.exe", "C:\\", "C:\\..\\kodi.exe",
		"C:\\a\\..\\Windows\\System32\\cmd.exe", "C:\\a\\.\\kodi.exe", "C:\\a\\kodi.exe:evil.exe", "C:\\a\\ko\"di.exe", "C:\\a\\ko|di.exe",
		"C:\\a\\ko*di.exe", "C:\\a\\kodi.exe.", "C:\\a \\kodi.exe", "C:\\a\\\\kodi.exe", "C:\\a\\ko\ndi.exe", "C:\\a\\ko\u0001di.exe", "C:\\a\\ko\u007fdi.exe",
		"C:\\" + "a\\".repeat(140) + "kodi.exe", "file:///C:/kodi.exe", "/usr/bin/kodi.exe"]
	var leaked: Array = weird.filter(func(s: String) -> bool: return A.path_problem(s) == "")
	check(leaked.is_empty(), "%d seltsame Pfade abgelehnt%s" % [weird.size(), ("" if leaked.is_empty() else ": " + str(leaked))])
	check(A.path_problem(42) != "" and A.path_problem(null) != "", "kein Text: abgelehnt")
	check(A.blocked_name("CMD.EXE") and A.blocked_name("powershell_ise") and A.blocked_name("python3") and not A.blocked_name("kodi.exe")
			and not A.blocked_name("Plex HTPC.exe") and not A.blocked_name("cmdline-tool.exe"), "Sperrliste nach Namen (mit Fassungsnummer)")

	print("Startparameter und Namen")
	check(A.args_ok([]) and A.args_ok(["--fullscreen", "stream", "Mein PC", "Desktop"]), "Liste aus Text")
	check(not A.args_ok("--fullscreen") and not A.args_ok([1]) and not A.args_ok([""]) and not A.args_ok(["a\nb"]) and not A.args_ok(["x".repeat(261)]),
			"kein Text, leer, Steuerzeichen, zu lang: abgelehnt")
	var many: Array = []
	for i in 17:
		many.append("a")
	check(not A.args_ok(many), "höchstens %d Parameter" % A.ARGS_MAX)
	check(A.clean_name("  Netflix\u0001\n ") == "Netflix", "Steuerzeichen weg, getrimmt")
	check(A.clean_name("abc\u202Eexe.txt") == "abcexe.txt" and A.clean_name("a\u200Bb") == "ab", "Richtungs- und unsichtbare Zeichen weg")
	check(A.clean_name("x".repeat(200)).length() == A.NAME_MAX and A.clean_name(5) == "", "Länge begrenzt, kein Text: leer")

	print("Kennungen der Apps")
	var id1 := A.make_id("store", "4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App")
	check(A.is_ext_id(id1) and id1 == A.make_id("store", "4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App"), "feste Kennung: " + id1)
	check(A.make_id("prog", "C:\\Kodi\\kodi.exe") == A.make_id("prog", "c:\\kodi\\KODI.EXE"), "Pfad ohne Groß/klein")
	check(not A.is_ext_id("music") and not A.is_ext_id("x123") and not A.is_ext_id("xZZZZZZZZZZ") and not A.is_ext_id("x0123456789\n"), "andere Kennungen nicht")
	check(not LeisteOben.is_app_id("games") and LeisteOben.is_app_id("music") and LeisteOben.is_app_id(id1), "eingebaut und eigene zählen als App")



func _speichern() -> void:
	print("Speichern, Reihenfolge, Entfernen")
	Config.set_value(A.KEY, [])
	Config.set_value("apps.order", [])
	Config.set_value("apps.hidden", [])
	var r1 := A.add_store("4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App", "Netflix")
	var r2 := A.add_prog("C:\\Program Files\\Kodi\\kodi.exe", "Kodi")
	var r3 := A.add_prog("C:\\Program Files\\Moonlight Game Streaming\\Moonlight.exe")
	check(bool(r1.ok) and bool(r2.ok) and bool(r3.ok) and bool(r1.neu), "Store-App und zwei Programme hinzugefügt")
	check(not bool(A.add_prog("C:\\Windows\\System32\\cmd.exe").ok) and not bool(A.add_store("bad!x", "x").ok), "Shell und falsche Kennung: nicht")
	check(not bool(A.add_prog("C:\\x\\kodi.exe", "", ["a\nb"]).ok), "falsche Parameter: nicht")
	var again := A.add_store("4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App", "Netflix")
	check(bool(again.ok) and not bool(again.neu) and A.entries().size() == 3, "doppelt: dieselbe App, keine zweite")
	var es := A.entries()
	check(es.map(func(e: Dictionary) -> String: return str(e.name)) == ["Netflix", "Kodi", "Moonlight"], "Reihenfolge des Hinzufügens, Name aus der Datei")
	check(str(es[1].path) == "C:\\Program Files\\Kodi\\kodi.exe" and es[1].args == [], "Pfad und Parameter gespeichert")
	# Von Hand verändert: falsche Kennung, Shell, unbekannte Art, Zusatzfelder.
	var raw: Array = (Config.get_value(A.KEY, []) as Array).duplicate(true)
	raw.append({ "id": A.make_id("prog", "C:\\x\\kodi.exe"), "kind": "prog", "name": "Böse", "path": "C:\\Windows\\System32\\cmd.exe", "args": [] })
	raw.append({ "id": "x0000000000", "kind": "prog", "name": "Falsch", "path": "C:\\x\\kodi.exe", "args": [] })
	raw.append({ "id": A.make_id("web", "x"), "kind": "web", "name": "Web", "url": "https://x" })
	raw.append("Text")
	(raw[0] as Dictionary)["extra"] = "weg"
	Config.set_value(A.KEY, raw)
	es = A.entries()
	check(es.size() == 3 and not (es[0] as Dictionary).has("extra"), "veränderte Einträge fallen weg, Zusatzfelder auch")
	var all := LeisteOben.all_apps()
	var ids: Array = all.map(func(t: Dictionary) -> String: return str(t.id))
	check(ids.slice(ids.size() - 3) == [str(r1.id), str(r2.id), str(r3.id)] and ids.has("music"), "Apps: eingebaute, dahinter die eigenen")
	Config.set_value("apps.order", [str(r3.id), "music"])
	var arr: Array = Q.arrange(all, Config.get_value("apps.order", []), [str(r2.id)]).map(func(t: Dictionary) -> String: return str(t.id))
	check(arr[0] == str(r3.id) and arr[1] == "music" and not arr.has(str(r2.id)) and arr.has(str(r1.id)), "eigene Reihenfolge, Ausgeblendetes fehlt")
	Config.safe_mode = true
	check(not LeisteOben.all_apps().any(func(t: Dictionary) -> bool: return A.is_ext_id(str(t.id))), "sicherer Modus: keine eigenen Apps")
	Config.safe_mode = false
	Config.set_value("apps.hidden", [str(r3.id)])
	check(A.remove(str(r3.id)) and A.entries().size() == 2, "entfernt")
	check(not (Config.get_value("apps.order", []) as Array).has(str(r3.id)) and not (Config.get_value("apps.hidden", []) as Array).has(str(r3.id)),
			"auch aus Reihenfolge und Ausgeblendetem")
	check(not A.remove(str(r3.id)), "zweimal entfernen: nichts")
	var lots: Array = []
	for i in A.MAX + 5:
		lots.append({ "id": A.make_id("prog", "C:\\a\\p%d.exe" % i), "kind": "prog", "name": "P%d" % i, "path": "C:\\a\\p%d.exe" % i, "args": [] })
	Config.set_value(A.KEY, lots)
	check(A.entries().size() == A.MAX and not bool(A.add_prog("C:\\a\\neu.exe").ok), "höchstens %d eigene Apps" % A.MAX)
	Config.set_value(A.KEY, [])



func _bestaetigung() -> Dictionary:
	print("Bestätigung (erster Start, Sicherung)")
	DirAccess.remove_absolute(Config.path(A.OK_FILE))
	var st := A.add_store("Disney.37853FC22B2CE_6rarf9sa4v8jt!App", "Disney+")
	var pr := A.add_prog("C:\\Kodi\\kodi.exe", "Kodi")
	var est := A.get_entry(str(st.id))
	var epr := A.get_entry(str(pr.id))
	check(not A.needs_ask(est), "Store-App aus der Liste: gleich bestätigt")
	check(A.needs_ask(epr), "Programm: erster Start fragt nach")
	A.confirm(epr)
	check(not A.needs_ask(epr), "einmal bestätigt: fragt nicht mehr")
	var changed := epr.duplicate(true)
	changed["args"] = ["--evil"]
	check(A.needs_ask(changed), "andere Parameter: fragt wieder")
	check(Backup.APPS_OK == A.OK_FILE and not Backup.allowed(A.OK_FILE) and not Backup.allowed(A.LOGO_DIR + "/x0123456789.png"), "Bestätigung und Logos kommen in keine Sicherung")
	check(not A.OK_FILE.begins_with("profiles") and not Config.path(A.OK_FILE).contains("/profiles/"), "Bestätigung gilt für diesen PC")
	# Nach dem Wiederherstellen: Einträge da (aus settings.json), Bestätigungen nicht.
	Config.save_settings()
	var bk := Backup.create(Config.data_dir, "hand")
	check(bool(bk.get("ok", false)) and not A.needs_ask(est), "Sicherung angelegt, Store-App noch bestätigt")
	var msg := Backup.restore_now(Config.data_dir, str(bk.get("path", "")))
	check(msg.begins_with("Sicherung") and A.needs_ask(est) and A.needs_ask(epr), "nach dem Wiederherstellen fragt jede App einmal")
	Config.write_json(Config.path(A.OK_FILE), ["kein-hash", 5, "a".repeat(64)])
	check(A.needs_ask(epr), "kaputte Bestätigungsdatei: fragt")
	A.confirm(epr)
	A.remove(str(pr.id))
	check(A.needs_ask(epr), "entfernt: Bestätigung weg")

	return est


func _start_und_liste(est: Dictionary) -> void:
	print("Start wie ein Spiel")
	var g := A.launch_game(est)
	check(str(g.source) == "app" and LauncherScript.is_app(g) and str(g.id) == "app:" + str(est.id) and str(g.title) == "Disney+", "Quelle „app“, eigene Kennung")
	check(not LauncherScript.is_app({ "source": "pc" }) and not LauncherScript.is_app({}), "Spiele sind keine Apps")
	var plan := LauncherScript.quit_plan("app", 1234, false)
	check(bool(plan.baum) and not bool(plan.ordner) and not bool(plan.vorhang), "Schließen: höflich, dann nur der eigene Prozessbaum")
	check(A.media_id(est) == "Disney.37853FC22B2CE_6rarf9sa4v8jt!App" and A.media_id({ "kind": "prog", "path": "C:\\Kodi\\kodi.exe" }) == "kodi.exe",
			"Mediensitzung: AUMID bzw. Dateiname")
	check(A.valid_media_id("kodi.exe") and A.valid_media_id("Plex HTPC.exe") and not A.valid_media_id("kodi.exe\n") and not A.valid_media_id("a;b.exe")
			and not A.valid_media_id("x.dll"), "Kennung der Mediensitzung geprüft")
	check(HelperScript.FAST.has("app-start") and HelperScript.FAST.has("app-window"), "Start und Fenstersuche auf dem schnellen Weg")

	print("Liste der Store-Apps vom Helfer")
	var lst := A.clean_store_list({ "apps": [
		{ "aumid": "SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify", "name": "Spotify" },
		{ "aumid": "4DF9E0F8.Netflix_mcm4njqhnhss8!Netflix.App", "name": "Netflix\u0007" },
		{ "aumid": "4df9e0f8.netflix_mcm4njqhnhss8!netflix.app", "name": "Doppelt" },
		{ "aumid": "böse; calc", "name": "x" },
		{ "aumid": "Foo.Bar_0123456789abc!App", "name": "ms-resource:AppName" },
		{ "aumid": 5 }, "Text", { "name": "ohne Kennung" },
	] })
	check(lst.size() == 3, "ungültige und doppelte fallen weg")
	check(lst.map(func(a: Dictionary) -> String: return str(a.name)) == ["Foo.Bar", "Netflix", "Spotify"], "nach Namen sortiert, Namen bereinigt, ohne Ressource-Text")
	check(A.clean_store_list("x").is_empty() and A.clean_store_list({ "apps": "x" }).is_empty(), "falsche Form: leer")
	var big: Array = []
	for i in A.STORE_MAX + 50:
		big.append({ "aumid": "Pkg.N%d_0123456789abc!App" % i, "name": "N%d" % i })
	check(A.clean_store_list({ "apps": big }).size() == A.STORE_MAX, "höchstens %d Einträge" % A.STORE_MAX)
	var kat := A.katalog_rows(A.demo_store_apps())
	var kn: Dictionary = {}
	for k in kat:
		kn[str(k.name)] = not (k.app as Dictionary).is_empty()
	check(kn["Netflix"] and kn["Disney+"] and kn["Prime Video"] and not kn["Crunchyroll"] and not kn["Plex"], "Katalog findet die installierten Dienste")
	check(kat.size() == A.KATALOG.size() and str(kat[0].name) == "Netflix", "Katalog in fester Reihenfolge")
	check(A.store_search_url("Disney+") == "ms-windows-store://search/?query=Disney%2B", "Store-Suche mit kodiertem Namen")

	print("Logo")
	var lid := str(est.id)
	check(not A.save_logo(lid, "kein base64") and not A.save_logo(lid, Marshalls.raw_to_base64("GIF89a".to_utf8_buffer())), "kein PNG: nicht")
	check(not A.save_logo("../x", Marshalls.raw_to_base64(_png(16))), "falsche Kennung: nicht")
	check(not A.save_logo(lid, Marshalls.raw_to_base64(_png(2048))), "zu groß: nicht")
	check(A.save_logo(lid, Marshalls.raw_to_base64(_png(64))) and A.logo_path(lid) != "", "PNG geprüft und neu gespeichert")
	check(str(A.launch_game(est).images.logo) == A.logo_path(lid), "Logo geht an den Start (keine Bilder aus dem Netz)")

	print("Sperrliste in Uzai und Helfer gleich")
	var src := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	var m := RegEx.create_from_string("\\$script:AppGesperrt = @\\(([^)]*)\\)").search(src)
	var ps: Array = []
	if m:
		for x in m.get_string(1).split(","):
			ps.append(x.strip_edges().trim_prefix("'").trim_suffix("'"))
	ps.sort()
	var gd: Array = A.GESPERRT.duplicate()
	gd.sort()
	check(m != null and ps == gd, "dieselben %d Namen" % gd.size())
	for cmd in ["'store-apps'", "'app-logo'", "'app-media'", "'app-start'", "'prog-check'", "'app-window'"]:
		check(src.contains("        " + cmd + " {"), "Helfer kennt " + cmd)
	check(src.contains("$psi.UseShellExecute = $false") and src.contains("[Xml.DtdProcessing]::Prohibit"), "Programme ohne Shell, Manifest ohne DTD")


func _png(px: int) -> PackedByteArray:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.1, 0.1))
	return img.save_png_to_buffer()

extends Node
## Einmal-Code für die Epic-Anmeldung im Spiel (wie Legendary: -AUTH_PASSWORD=<Exchange-Code>) ohne
## Netz: Prüfung der Antwort von …/oauth/exchange (auch böse: Leerzeichen, Anführungszeichen, &,
## Zeilenumbruch, überlang, falscher Typ), Startparameter als Liste in Legendarys Reihenfolge, wann
## Uzai überhaupt einen Code holt, Wege ohne Helfer ohne Code, Protokoll ohne Code.
## Mit UZAI_HELPER_SHELL=<pwsh> zusätzlich: die Liste im Helfer (Join-StartArgv) – Quoten wie
## CommandLineToArgvW, nur für .exe, Steuerzeichen und Mengen abgelehnt, Fehler ohne Wert.
## Aufruf: UZAI_DATA=<leer> godot --headless --path . res://tests/logic_epic_spielcode.tscn → „Ergebnis: alles ok“
## Den Ablauf mit Netz prüft tests/net_epic_spielcode.gd gegen tests/fake_epic.py.

const On := preload("res://src/library/epic_online.gd")
const M := preload("res://src/library/epic_manifest.gd")
const EI := preload("res://src/core/epic_install.gd")
const HelperScript := preload("res://src/core/helper.gd")
const CODE := "0123456789abcdef0123456789abcdef"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	print("Antwort von oauth/exchange prüfen")
	_parse()
	print("Startparameter als Liste")
	_args()
	print("Wann Uzai einen Code holt")
	_wanted()
	print("Ohne Helfer und im Protokoll nie der Code")
	_no_leak()
	print("Helfer: Liste zur Befehlszeile")
	_pwsh()
	print("")
	print("Ergebnis: alles ok" if fails == 0 else "Ergebnis: %d FEHLER" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _ex(code: Variant, status := 200) -> String:
	return On.parse_exchange(status, { "expiresInSeconds": 300, "code": code, "creatingClientId": On.CLIENT_ID })


func _parse() -> void:
	check(_ex(CODE) == CODE, "Epics Antwort: 32 Zeichen 0–9/a–f")
	check(_ex(CODE, 204) == CODE and _ex(CODE, 401) == "" and _ex(CODE, 500) == "" and _ex(CODE, 0) == "", "nur mit 2xx")
	var bad := {
		"Leerzeichen": "0123456789abcdef 123456789abcdef",
		"Leerzeichen am Ende": CODE + " ",
		"Anführungszeichen": "0123456789abcdef\"-x=1\"456789abcd",
		"einfaches Anführungszeichen": "0123456789abcdef'0123456789abcde",
		"&": "0123456789abcdef&calc&0123456789",
		"| und ^": "0123456789abcdef|calc^0123456789",
		"Zeilenumbruch am Ende": CODE + "\n",
		"Zeilenumbruch innen": "0123456789abcdef\n0123456789abcdef",
		"Wagenrücklauf": CODE + "\r",
		"Tab": "0123456789abcdef\t0123456789abcde",
		"Steuerzeichen": "0123456789abcdef" + String.chr(1) + "123456789abcdef",
		"überlang": "a".repeat(On.EXCHANGE_MAX + 1),
		"sehr lang": "0".repeat(100000),
		"zu kurz": "abc",
		"leer": "",
		"Großbuchstaben": CODE.to_upper(),
		"Prozent": "0123456789abcdef%PATH%0123456789",
		"Minus (zweiter Parameter)": "0123456789abcdef -EpicPortal=x 1",
		"Unicode-Ziffern": "０１２３456789abcdef0123456789abcdef",
		"Backslash": "0123456789abcdef\\0123456789abcde",
	}
	for k in bad.keys():
		check(_ex(bad[k]) == "", "abgelehnt: %s" % k)
	check(_ex(1234567890123456) == "" and _ex(null) == "" and _ex([CODE]) == "" and _ex({ "code": CODE }) == "" and _ex(true) == "",
		"abgelehnt: Zahl, null, Liste, Objekt, Wahrheitswert")
	check(On.parse_exchange(200, null) == "" and On.parse_exchange(200, [CODE]) == "" and On.parse_exchange(200, CODE) == ""
		and On.parse_exchange(200, {}) == "" and On.parse_exchange(200, { "exchangeCode": CODE }) == "", "abgelehnt: kein Objekt oder kein „code“")
	check(On.exchange_ok("a".repeat(On.EXCHANGE_MAX)) and On.exchange_ok("0".repeat(On.EXCHANGE_MIN)) and not On.exchange_ok("0".repeat(On.EXCHANGE_MIN - 1)),
		"Längengrenzen %d–%d" % [On.EXCHANGE_MIN, On.EXCHANGE_MAX])


func _args() -> void:
	var a := M.launch_args("-SaveToUserDir", "Kinglet", "ns1", "Max Muster", "acc1", "de", CODE)
	var want := PackedStringArray(["-SaveToUserDir", "-AUTH_LOGIN=unused", "-AUTH_PASSWORD=" + CODE, "-AUTH_TYPE=exchangecode",
		"-epicapp=Kinglet", "-epicenv=Prod", "-EpicPortal", "-epicusername=Max Muster", "-epicuserid=acc1", "-epiclocale=de",
		"-epicsandboxid=ns1"])
	check(a == want, "Reihenfolge wie Legendary (core.py): Manifest, AUTH_*, epicapp, epicenv, EpicPortal, Name, ID, Sprache, Sandbox")
	check(a.has("-epicusername=Max Muster"), "Name mit Leerzeichen bleibt ein Argument (Liste, keine Zeile)")
	for k in ["0123456789abcdef 123456789abcdef", CODE + "\n", "0123456789abcdef\"x\"3456789abcde", "0123456789abcdef&calc&0123456789",
			"f".repeat(65), ""]:
		var b := M.launch_args("", "Kinglet", "ns1", "Max", "acc1", "de", k)
		check(not "\n".join(b).contains("AUTH"), "böser Code %s: gar keine AUTH-Parameter" % JSON.stringify(k).left(40))
	var c := M.launch_args("", "Kinglet\n", "ns1\n", "Max\n", "acc1\n", "de\n", CODE)
	check(not "|".join(c).contains("\n") and not "|".join(c).contains("epicapp") and not "|".join(c).contains("epicusername")
		and not "|".join(c).contains("epicuserid") and not "|".join(c).contains("epiclocale"), "Zeilenumbruch am Ende von Name, App, ID, Sprache: weggelassen")
	var d := M.launch_args("", "Kinglet", "ns1", "Max \"x", "acc1", "de-DE", CODE)
	check(not "|".join(d).contains("epicusername") and d.has("-epiclocale=de-DE"), "Name mit Anführungszeichen weggelassen, Sprache de-DE")


func _wanted() -> void:
	check(EI.game_login_wanted(true, true, "D:/Spiele/Kinglet/Kinglet.exe", true), "an, angemeldet, .exe, Helfer: ja")
	check(EI.game_login_wanted(true, true, "D:/Spiele/K/SPIEL.EXE", true), "auch .EXE groß")
	check(not EI.game_login_wanted(false, true, "D:/a.exe", true), "ausgeschaltet: nein")
	check(not EI.game_login_wanted(true, false, "D:/a.exe", true), "Epic-Konto nicht verbunden: nein")
	check(not EI.game_login_wanted(true, true, "D:/a.exe", false), "ohne Helfer: nein")
	for e in ["D:/start.bat", "D:/start.cmd", "D:/x.lnk", "D:/x.url", "D:/x.ps1", "D:/x.exe.bat", "D:/x"]:
		check(not EI.game_login_wanted(true, true, e, true), "kein Code für %s" % e.get_file())
	check(bool(Config.get_value("accounts.epic_game_login", false)), "Standard: an")
	# Ohne Anmeldung holt start_argv keinen Code und fragt nichts im Netz.
	check(not "|".join(EI.launch_argv({ "epic": { "app": "Kinglet", "namespace": "ns1" } })).contains("AUTH"), "launch_argv ohne Code: keine AUTH-Parameter")


func _no_leak() -> void:
	var a := M.launch_args("-x", "Kinglet", "ns1", "Max", "acc1", "de", CODE)
	var w := EI.without_code(a)
	check(w.size() == a.size() - 3 and not "|".join(w).contains(CODE) and not "|".join(w).contains("AUTH") and w.has("-epicapp=Kinglet") and w.has("-x"),
		"ohne Helfer: dieselben Parameter ohne Code")
	var l := HelperScript.redact('main: Befehl start ging nicht: {"argv":["-AUTH_PASSWORD=%s","-x"]} "-AUTH_PASSWORD=%s" -auth_password=%s' % [CODE, CODE, CODE])
	check(not l.contains(CODE) and l.contains("-x") and l.contains("start ging nicht"), "Helfer-Protokoll: Code unkenntlich („%s“)" % l.left(70))
	check(HelperScript.redact("nichts Geheimes") == "nichts Geheimes", "sonst unverändert")
	var wa := HelperScript.win_args(a, true)
	check(wa.has("-AUTH_PASSWORD=" + CODE) and wa.size() == a.size(), "Windows-Argumente: Code bleibt ein Argument, unverändert")
	var src := FileAccess.get_file_as_string("res://src/library/epic_account.gd")
	var body := src.substr(src.find("func exchange_code"), src.find("static func exchange_url") - src.find("func exchange_code"))
	check(body.contains("_log(") and not body.contains("_log(\"%s") and not body.contains("code]") and not body.contains("r.data") and not body.contains("print("),
		"exchange_code protokolliert nur den HTTP-Code")
	var la := FileAccess.get_file_as_string("res://src/core/launcher.gd")
	check(la.contains("EpicInstallS.without_code(argv)") and not la.contains("launch_line"), "Launcher: ohne Helfer ohne Code, keine Startzeile als Text")
	check(On.ACCOUNT_HOST.begins_with("https://") and On.ACCOUNT_HOST.ends_with(".ol.epicgames.com"), "Anmeldedienst nur über https bei Epic")
	check(OS.get_environment("UZAI_TEST_LOOPBACK") == "1" or Library.epic_account.exchange_url() == On.ACCOUNT_HOST + "/account/api/oauth/exchange",
		"ohne Probe-Schalter: Epics Adresse, egal was UZAI_EPIC_API sagt")


# --- PowerShell 7 ----------------------------------------------------------------------------

func _pwsh() -> void:
	if HelperScript._test_shell() == "":
		print("  (PowerShell-Prüfung übersprungen: UZAI_HELPER_SHELL nicht gesetzt)")
		return
	var dir := OS.get_cache_dir().path_join("uzai-spielcode-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	var script := dir.path_join("uzai-helper.ps1")
	var f := FileAccess.open(script, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string("res://helper/uzai-helper.ps1"))
	f.close()
	var probe := dir.path_join("probe.ps1")
	var pf := FileAccess.open(probe, FileAccess.WRITE)
	pf.store_string("""
$src = (Get-Content -Raw $args[0]) -replace "`r`n", "`n"
$m = [regex]::Match($src, '(?ms)^function Join-StartArgv\\(.*?^\\}')
if (-not $m.Success) { 'FEHLT'; exit 1 }
Invoke-Expression $m.Value
function T($list, $ext) {
	try { 'R:' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Join-StartArgv $list $ext))) }
	catch { 'E:' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_.Exception.Message)) }
}
T @('-AUTH_PASSWORD=%s', '-epicusername=Max Muster', 'a"b', 'C:\\Pfad mit\\') '.exe'
T @('-AUTH_PASSWORD=%s') '.bat'
T @('-AUTH_PASSWORD=%s') '.cmd'
T @("-x`n-y", 'ok') '.exe'
T @(1..65 | ForEach-Object { '-a' }) '.exe'
T @(5) '.exe'
T @('') '.exe'
T $null '.bat'
""" % [CODE, CODE, CODE])
	pf.close()
	var out: Array = []
	OS.execute(HelperScript._test_shell(), PackedStringArray(["-NoProfile", "-NonInteractive", "-File", probe, script]), out, true)
	var res: Array = []
	for line in str(out[0] if not out.is_empty() else "").split("\n"):
		var t := line.strip_edges()
		if t.begins_with("R:") or t.begins_with("E:"):
			res.append([t.left(1), Marshalls.base64_to_utf8(t.substr(2))])
	check(res.size() == 8, "Probe lief (%d Ergebnisse)" % res.size())
	if res.size() != 8:
		return
	var want := "-AUTH_PASSWORD=%s \"-epicusername=Max Muster\" \"a\\\"b\" \"C:\\Pfad mit\\\\\"" % CODE
	check(res[0][0] == "R" and res[0][1] == want, "gequotet wie CommandLineToArgvW (%s)" % str(res[0][1]).left(80))
	check(res[1][0] == "E" and res[2][0] == "E", "Batchdatei (.bat/.cmd): abgelehnt, nie über cmd")
	check(res[3][0] == "E" and res[4][0] == "E" and res[5][0] == "E" and res[6][0] == "E", "Zeilenumbruch, mehr als 64, keine Zeichenkette, leer: abgelehnt")
	check(res[7][0] == "R" and res[7][1] == "", "ohne Liste: nichts (auch bei .bat wie bisher)")
	check(res.all(func(r): return not str(r[1]).contains(CODE) or r == res[0]), "Fehlermeldungen nennen den Code nie")
	# Der echte Befehl „start“: eine Batchdatei mit Liste scheitert, bevor irgendetwas startet.
	for exe in ["/fehlt/start.bat", "/fehlt/start.CMD"]:
		var o2: Array = []
		OS.execute(HelperScript._test_shell(), PackedStringArray(["-NoProfile", "-NonInteractive", "-File", script, "-Once",
			Marshalls.utf8_to_base64(JSON.stringify({ "id": 1, "cmd": "start", "args": { "exe": exe, "argv": ["-AUTH_PASSWORD=" + CODE], "args": "" } }))]), o2, true)
		var reply := {}
		for line in str(o2[0] if not o2.is_empty() else "").split("\n"):
			var jp := JSON.new()
			if line.strip_edges().begins_with("{") and jp.parse(line.strip_edges()) == OK and jp.data is Dictionary:
				reply = jp.data
		check(reply.has("ok") and not bool(reply.ok) and str(reply.get("error", "")).contains(".exe") and not JSON.stringify(reply).contains(CODE),
			"Helfer „start“ %s mit Liste: abgelehnt, Meldung ohne Code" % exe.get_file())

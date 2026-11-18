extends Node
## Fehlende Launcher (Punkt 115) und RetroAchievements per Handy (Punkt 49), ohne Netz:
## nur offizielle HTTPS-Seiten, nur sicher Fehlendes anbieten; Handy-Formular mit zwei Feldern
## (nur erlaubte Felder, alles maskiert); Name und Schlüssel prüfen, bevor etwas gespeichert wird.
## Aufruf: godot --headless --path . res://tests/logic_launcher_ra.tscn

const LauncherSites := preload("res://src/library/launcher_sites.gd")
const EpicScanner := preload("res://src/library/epic_scanner.gd")
const RemoteS := preload("res://src/core/remote.gd")
const AchievementsS := preload("res://src/core/achievements.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _ready() -> void:
	_launchers()
	_form()
	await _ra()
	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _launchers() -> void:
	print("Fehlende Launcher")
	check(LauncherSites.missing({ "steam": false, "epic": true, "ea": false }, {}) == ["steam", "ea"], "nur die sicher fehlenden, in fester Reihenfolge")
	check(LauncherSites.missing({}, {}).is_empty(), "nichts bekannt (anderes System): nichts anbieten")
	check(LauncherSites.missing({ "steam": false }, { "steam": false }).is_empty(), "ausgeschaltete Quelle: nichts anbieten")
	var hosts := { "steam": "https://store.steampowered.com/", "epic": "https://store.epicgames.com/", "ea": "https://www.ea.com/",
		"gog": "https://www.gog.com/", "ubisoft": "https://ubisoftconnect.com/", "battlenet": "https://download.battle.net/",
		"xboxpc": "https://www.xbox.com/", "amazon": "https://gaming.amazon.com/", "itch": "https://itch.io/", "riot": "https://www.riotgames.com/" }
	for id in LauncherSites.ORDER:
		check(LauncherSites.url(id).begins_with(hosts[id]), "offizielle HTTPS-Seite: " + id)
	check(LauncherSites.url("xyz") == "" and LauncherSites.site("x").is_empty(), "Unbekanntes: keine Adresse")
	var base := Config.path("launcher_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(base)
	check(not EpicScanner.launcher_present(base), "ohne ProgramData\\Epic: Epic fehlt")
	DirAccess.make_dir_recursive_absolute(base.path_join("Epic/EpicGamesLauncher"))
	check(EpicScanner.launcher_present(base), "mit ProgramData\\Epic\\EpicGamesLauncher: Epic da")
	Library.launchers = { "steam": false, "ea": true }
	check(Library.launcher_missing("steam") and not Library.launcher_missing("ea") and not Library.launcher_missing("epic"),
			"Library: fehlt nur, was sicher fehlt")
	Library.launchers = {}


func _form() -> void:
	print("Handy-Formular mit mehreren Feldern")
	var v := RemoteS.form_values("user=Anna%20B&key=abc123&evil=1&user=zweiter&kaputt&=leer", ["user", "key"])
	check(v == { "user": "Anna B", "key": "abc123" }, "nur erlaubte Felder, erster Wert zählt, Kaputtes ignoriert")
	check(RemoteS.form_values("user=" + "x".repeat(5000), ["user"]).user.length() == RemoteS.FIELD_MAX, "Wert gekürzt")
	check(RemoteS.form_values("key=a%2Bb+c", ["key"]).key == "a+b c", "Plus und Prozent wie im Formular")
	var html := RemoteS.form_html({ "title": "<b>RA</b>", "hint": "x'y", "link": "https://retroachievements.org/settings",
		"fields": [{ "name": "user", "label": "Name <i>" }, { "name": "key", "label": "Schlüssel", "secret": true }] })
	check(html.contains("&lt;b&gt;RA&lt;/b&gt;") and html.contains("Name &lt;i&gt;") and html.contains("x&#39;y") and not html.contains("<i>"),
			"alles Angezeigte maskiert")
	check(html.contains("name='user' type='text'") and html.contains("name='key' type='password'"), "Schlüssel als Passwortfeld")
	check(html.contains("href='https://retroachievements.org/settings'"), "Link zum Anbieter")
	var bad := RemoteS.form_html({ "title": "t", "hint": "", "link": "javascript:alert(1)", "fields": [{ "name": "user", "label": "a" }] })
	check(not bad.contains("javascript:"), "nur https-Links")
	check(Remote.phone_form_begin("t", "t", [{ "name": "User" }]) == "" and Remote.phone_form_begin("t", "t", [{ "name": "a b" }]) == "",
			"Feldnamen nur aus Kleinbuchstaben")
	# Anleitung über den Feldern (Discord: eigene App) und Ziffern-Muster ohne Skript.
	var sh := RemoteS.form_html({ "title": "ID", "hint": "", "link": "https://discord.com/developers/applications",
		"fields": [{ "name": "id", "label": "Application ID", "pattern": "[0-9]{17,20}", "inputmode": "numeric" }],
		"steps": [{ "text": "Schritt <b>1</b>" }, { "text": "Zwei", "copy": ["http://localhost", "x'><script>"] }] })
	check(sh.contains("<ol class='steps'><li>Schritt &lt;b&gt;1&lt;/b&gt;</li>") and sh.contains("value='http://localhost'")
			and sh.contains("value='x&#39;&gt;&lt;script&gt;'") and not sh.contains("<script>"), "Schritte und Texte zum Kopieren, maskiert")
	check(sh.contains("pattern='[0-9]{17,20}' required") and sh.contains("inputmode='numeric'") and not sh.contains("autofocus"),
			"Ziffern-Muster und Zahlentastatur; mit Anleitung kein Sprung ins Feld")
	var boese := RemoteS.form_html({ "title": "t", "hint": "", "fields": [{ "name": "id", "label": "a", "pattern": "' onfocus='x", "inputmode": "' x" }] })
	check(not boese.contains("pattern=") and not boese.contains("inputmode=") and not boese.contains("onfocus"), "fremde Muster werden nicht übernommen")


func _ra() -> void:
	print("RetroAchievements prüfen")
	check(AchievementsS.ra_format_error("Anna", "a".repeat(32)) == "", "Name und 32-Zeichen-Schlüssel sehen richtig aus")
	check(AchievementsS.ra_format_error("A", "a".repeat(32)) != "", "zu kurzer Name")
	check(AchievementsS.ra_format_error("Anna&y=x", "a".repeat(32)) != "", "Name mit Sonderzeichen")
	check(AchievementsS.ra_format_error("Anna", "kurz") != "", "zu kurzer Schlüssel")
	check(AchievementsS.ra_format_error("Anna", "a".repeat(31) + "!") != "", "Schlüssel mit Sonderzeichen")
	var ok := AchievementsS.ra_check_result(200, { "User": "Anna", "TotalPoints": 1234 })
	check(bool(ok.ok) and ok.name == "Anna" and int(ok.points) == 1234, "passt: Name und Punkte")
	check(not bool(AchievementsS.ra_check_result(401, { "message": "Unauthenticated." }).ok), "falscher Schlüssel: 401")
	check(str(AchievementsS.ra_check_result(401, null).error).contains("Schlüssel"), "falscher Schlüssel: klare Meldung")
	check(str(AchievementsS.ra_check_result(404, null).error).contains("Benutzernamen"), "unbekannter Name: 404")
	check(str(AchievementsS.ra_check_result(200, {}).error).contains("Benutzernamen"), "unbekannter Name: leere Antwort")
	check(str(AchievementsS.ra_check_result(0, null).error).contains("nicht erreichbar"), "kein Netz")
	check(not bool(AchievementsS.ra_check_result(200, { "User": null }).ok), "ohne Namen kein Erfolg")
	var r: Dictionary = await Achievements.check_ra("x", "y")
	check(not bool(r.ok) and str(r.error) != "", "Falsches Format: gar nicht erst fragen")

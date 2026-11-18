extends RefCounted
## Protokoll des Players (logs/player.log): Einrichten von yt-dlp, Deno und mpv (Laden, Prüfsumme,
## Entpacken), Start von mpv, Steuerkanal, Abbrüche mit Grund. Ohne Benutzerpfade (USERPROFILE,
## APPDATA, LOCALAPPDATA und der Benutzername werden ersetzt), ohne Steuerzeichen, kurz.
## Vorher stand bei „Videos gehen nicht“ nirgends, woran es lag (Freund-Test 0.16.51).
##
## Reine Funktionen (anonym, mpv_grund) prüft tests/logic_videos.gd.

const Logdatei := preload("res://src/core/logdatei.gd")
const CrashGuard := preload("res://src/core/crash_guard.gd")

const MAX_BYTES := 200000


## Dieses Protokoll schicken Nutzer, wenn Videos nicht gehen: Adressen nur bis zum Host, Schlüssel, Tokens und
## IP-Adressen raus (CrashGuard.clean) – mpvs Fehlerzeile enthält sonst die ganze Stream-Adresse, bei Addons und
## Medienservern oft mit Schlüssel (X-Plex-Token, Debrid-Kennung im Pfad).
static func zeile(text: String) -> void:
	Logdatei.zeile(Config.path("logs/player.log"), sauber(text), MAX_BYTES)


static func sauber(text: String, env := {}) -> String:
	return CrashGuard.clean(anonym(text, env), [])


## Pfade und Namen des Benutzers unkenntlich: aus der Umgebung (oder, für Tests, aus env).
static func anonym(text: String, env := {}, laenge := 400) -> String:
	var t := text
	for v in ["LOCALAPPDATA", "APPDATA", "USERPROFILE"]:
		var e := str(env.get(v, OS.get_environment(v)))
		if e.length() > 3:
			t = t.replace(e, "%" + v + "%").replace(e.replace("\\", "/"), "%" + v + "%")
	var user := str(env.get("USERNAME", OS.get_environment("USERNAME")))
	if user.length() >= 2:
		# Übrige Stellen mit dem Namen (anderes Laufwerk, Kurzform): C:\Users\<Name>\…
		t = RegEx.create_from_string("(?i)([\\\\/]Users[\\\\/])" + _re_esc(user) + "(?=[\\\\/]|$)").sub(t, "$1<Name>", true)
	var out := ""
	for ch in t:
		if ch.unicode_at(0) >= 0x20:
			out += ch
	return out.left(laenge)


static func _re_esc(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if ".^$*+?()[]{}|\\/".contains(ch) else ch
	return out


## Kurzer Grund für den Nutzer aus mpvs eigenem Protokoll (--log-file): der jüngste wichtige Fehler.
## Rückgabe { text: Satz für die Meldung, zeile: die Zeile aus dem Protokoll (gekürzt) }.
static func mpv_grund(log_text: String) -> Dictionary:
	# Von hinten: Bei einem schon laufenden mpv steht das jüngste Video am Ende.
	var lines := log_text.split("\n")
	lines.reverse()
	var fehler := ""
	for l in lines:
		var s := l.strip_edges()
		if s.contains("[ytdl_hook]") and (s.contains("ERROR:") or s.contains("failed")):
			fehler = s
			break
	if fehler == "":
		for l in lines:
			var s2 := l.strip_edges()
			if s2.contains("][e][") or s2.contains("][f][") or s2.contains("Error parsing option") or s2.contains("Failed to open") \
					or s2.contains("Failed to recognize"):
				fehler = s2
				break
	var low := fehler.to_lower()
	var text := "mpv hat sich gleich wieder beendet."
	if fehler == "":
		pass
	elif low.contains("sign in to confirm") or low.contains("not a bot"):
		text = "YouTube verlangt eine Bestätigung (Bot-Prüfung). Später noch einmal."
	elif low.contains("private video") or low.contains("video unavailable") or low.contains("this video is not available"):
		text = "Das Video ist nicht verfügbar."
	elif low.contains("requested format is not available"):
		text = "Diese Qualität gibt es hier nicht. Andere Qualität wählen."
	elif low.contains("http error 403") or low.contains("403 forbidden"):
		text = "Der Server lehnt ab (HTTP 403). yt-dlp ist vielleicht veraltet."
	elif low.contains("http error 429"):
		text = "Zu viele Anfragen (HTTP 429). Später noch einmal."
	elif low.contains("ytdl_hook") and (low.contains("not enough permissions") or low.contains("failed to run") or low.contains("is not recognized")):
		text = "yt-dlp startet nicht. Virenschutz prüfen oder unter Einstellungen → Videos neu laden."
	elif low.contains("ytdl_hook"):
		text = "yt-dlp konnte das Video nicht öffnen."
	elif low.contains("error parsing option") or (low.contains("option") and low.contains("not found")):
		text = "mpv kennt eine Option nicht. mpv unter Einstellungen → Videos neu laden."
	elif low.contains("failed to open") or low.contains("failed to recognize"):
		text = "Die Quelle ließ sich nicht öffnen."
	return { "text": text, "zeile": fehler.left(200) }

extends RefCounted
## Ablauf einer Anmeldung per Code am Handy (OAuth-Geräte-Anmeldung) als kleiner Zustandsautomat –
## gemeinsam für Twitch und YouTube wie am Fernseher (twitch_parse.gd, youtube_tv_parse.gd) und
## Spotify wie die Spotify-App (music_spotify.gd). Kein Netz, kein Zustand – darum offline prüfbar.
## flow: { phase: "code" | "done" | "error", wait, until, misses, msg }. phase ändert sich nur in schritt() (code →
## done oder error, danach fest; „Nochmal“ beginnt mit neu()). Die Anmelde-Ebene übernimmt done/error in ihren
## Zustand „anmeldung.code“ (Tabelle in src/ui/layers/yt_login.gd, Übersicht docs/ZUSTAENDE.md).


## Neuer Ablauf aus der Antwort auf die Code-Anfrage ({ interval, expires } in Sekunden).
static func neu(info: Dictionary, now: float) -> Dictionary:
	return { "phase": "code", "wait": float(info.get("interval", 5)), "until": now + float(info.get("expires", 1800)), "misses": 0, "msg": "" }


## Nächster Zustand nach einer Abfrage. state: "ok", "pending", "slow", "denied", "expired", "error"
## oder etwas anderes (Netz weg, Unerwartetes); err: Fehlertext der letzten Abfrage. texte:
##   offline    nach vier Fehlversuchen, wenn kein Fehlertext gezeigt wird
##   sofort     Fehlertext, der den Ablauf gleich beendet (der Dienst lehnt die Kennung ab), sonst ""
##   abgelehnt  Text für state "error": Ablauf gleich beenden (err geht vor); "" = wie Netz weg
##   grund      true: nach vier Fehlversuchen den Fehlertext zeigen, false: immer offline
static func schritt(flow: Dictionary, state: String, now: float, err: String, texte: Dictionary) -> Dictionary:
	var f := flow.duplicate()
	if f.phase != "code":
		return f
	if state == "ok":
		f.phase = "done"
		return f
	if now > float(f.until) or state == "expired":
		f.phase = "error"
		f.msg = "Der Code ist abgelaufen. „Nochmal versuchen“ holt einen neuen."
		return f
	match state:
		"pending":
			f.misses = 0
		"slow":
			f.wait = minf(float(f.wait) + 5.0, 60.0)
		"denied":
			f.phase = "error"
			f.msg = "Die Anmeldung wurde auf dem Handy abgelehnt."
		_:
			var abgelehnt := str(texte.get("abgelehnt", ""))
			if state == "error" and abgelehnt != "":
				f.phase = "error"
				f.msg = err if err != "" else abgelehnt
				return f
			# Netz weg oder Unerwartetes: ein paar Mal still weiter warten, dann Bescheid geben.
			f.misses = int(f.misses) + 1
			var sofort := str(texte.get("sofort", ""))
			if int(f.misses) >= 4 or (sofort != "" and err == sofort):
				f.phase = "error"
				f.msg = err if err != "" and bool(texte.get("grund", true)) else str(texte.offline)
	return f

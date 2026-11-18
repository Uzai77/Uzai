extends RefCounted
## Nicht stören: Hinweise von außen – Nachrichten (Steam, Discord), Discord-Benachrichtigungen,
## Freundschaftsanfragen, Angebote der Wunschliste, „Freund ist online“ – kommen still in die
## Mitteilungen (Punkt an der Glocke) statt als Pop-up: kein Bild, kein Ton, keine Vibration.
## Anrufe, Erfolge und Rückmeldungen auf eigene Drücke kommen weiter. Wer so etwas schickt, setzt
## in Toasts.show_toast die Option „stoert“.
## An/aus: Schnellmenü (Kachel „Nicht stören“), Guide → System → Mehr. Von selbst, solange ein
## Film im Player läuft (notify.ruhe_film, Standard an). Von Hand gilt es nur für diese Sitzung.

static var an := false


## Reine Entscheidung (tests/logic_komfort.gd).
static func ruhig(manuell: bool, bei_film: bool, film: bool) -> bool:
	return manuell or (bei_film and film)


## Läuft gerade ein Film oder eine Folge groß im Player?
static func film_laeuft() -> bool:
	return Video.watching() and Video.video.has("movies")


static func aktiv() -> bool:
	return ruhig(an, bool(Config.get_value("notify.ruhe_film", true)), film_laeuft())


## Zustand für Kachel und Zeile: „An“, „Beim Film“ (von selbst) oder "".
static func zustand() -> String:
	if an:
		return "An"
	return "Beim Film" if aktiv() else ""


static func umschalten() -> void:
	an = not an
	Toasts.show_toast("Nicht stören" if an else "Nicht stören aus", "Nachrichten kommen still in die Mitteilungen." if an else "", "bell",
			{ "quiet": true, "ms": 2000, "overlay": true })

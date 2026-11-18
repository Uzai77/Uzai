extends RefCounted
## Eine Zeile mit Zeitstempel an eine Protokolldatei hängen. Wird die Datei größer als max_bytes,
## fängt sie neu an (Protokolle sind zum Nachsehen da, nicht zum Aufbewahren). Stand vorher als
## eigener Block in fünfzehn Dateien – zehn davon ohne Prüfung, ob das Neuanlegen gelang.
##
## Was hineinkommt, entscheidet der Aufrufer: Zugangsdaten, Adressen mit Schlüsseln und Namen
## bleiben draußen (anonym(), redact(), log_sicher() an den Stellen, die so etwas sehen). Dazu
## prüft sauber() jede Zeile als letzte Sicherung.

const MAX_BYTES := 300000

## Konto-Kennungen: Discord (17 bis 20 Ziffern) und Steam (64 Bit, 17 Ziffern). Andere Zahlen in den Protokollen
## (Zeit in ms, Größen, App-IDs) sind kürzer. Angelegt erst beim ersten Gebrauch (sauber()): Mit einem Startwert an
## der Variablen waren sie leer, wenn die Datei als Abhängigkeit geladen wurde, bevor ihre statischen Werte standen –
## dann brach zeile() ab, und die Zeile fehlte im Protokoll.
static var _rx_kennung: RegEx
static var _rx_bearer: RegEx


## pfad: voller Pfad (Config.path("logs/….log")). nach_zeit: steht gleich hinter dem Zeitstempel.
static func zeile(pfad: String, text: String, max_bytes := MAX_BYTES, nach_zeit := "") -> void:
	DirAccess.make_dir_recursive_absolute(pfad.get_base_dir())
	var f := FileAccess.open(pfad, FileAccess.READ_WRITE if FileAccess.file_exists(pfad) else FileAccess.WRITE)
	if f == null:
		return
	if max_bytes > 0 and f.get_length() > max_bytes:
		f.close()
		f = FileAccess.open(pfad, FileAccess.WRITE)
		if f == null:
			return
	f.seek_end()
	f.store_line("%s%s  %s" % [Time.get_datetime_string_from_system(), nach_zeit, sauber(text)])
	f.close()


## Letzte Sicherung für jede Zeile, egal woher sie kommt – auch Texte fremder Bibliotheken: Das Discord-SDK schreibt
## Adressen wie …/api/v9/users/<Kennung>/messages in sein Protokoll, und Uzai reicht es nach discord.log weiter.
## Protokolle teilen Nutzer bei Fehlern; Kennungen von Konten und Bearer-Schlüssel gehören nicht hinein.
static func sauber(text: String) -> String:
	if _rx_kennung == null:
		_rx_kennung = RegEx.create_from_string("(?<![0-9])[0-9]{17,20}(?![0-9])")
	if _rx_bearer == null:
		_rx_bearer = RegEx.create_from_string("(?i)\\b(bearer\\s+)[A-Za-z0-9._~+/=-]{8,}")
	return _rx_bearer.sub(_rx_kennung.sub(text, "<Kennung>", true), "$1***", true)

extends Node
## Discord-Status beim Musikhören: „Hört …“ mit Titel, Künstler, Cover und Restzeit, dazu ein Knopf
## „Auf Spotify mithören“ – so sehen Discord-Freunde, was läuft, und können einsteigen. Nur wenn
## wirklich etwas läuft und gerade kein Spiel den Status belegt. Bei Steam erscheint nichts.

## Um so viele Sekunden muss sich der errechnete Beginn verschieben, damit es als Sprung im Titel gilt. Der Beginn
## schwankt von Abfrage zu Abfrage um eine Sekunde (Rundung); vorher zählten feste 5-Sekunden-Fächer, und ein Titel,
## dessen Beginn an einer Fachgrenze lag, wurde alle paar Sekunden neu an Discord geschickt.
const SPRUNG_S := 3

var _shown := ""        # welcher Titel zuletzt gesetzt wurde (URI bzw. Name), "" = nichts
var _shown_start := 0   # und mit welchem Beginn (Unix-Zeit)
var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = 3.0
	_timer.timeout.connect(update)
	add_child(_timer)
	_timer.start()
	Music.updated.connect(update)
	# Status abgeschaltet: sofort leeren (sonst stünde der Titel bis zum Ende in Discord).
	Config.changed.connect(func(k: String) -> void:
		if k.begins_with("accounts.discord_") and not wanted() and _shown != "":
			_shown = ""
			if not Launcher.in_game:
				Helper.run("presence-clear")
		elif k.begins_with("accounts.discord_"):
			update()
	)
	Launcher.ended.connect(func(_g: Dictionary, _s: int) -> void:
		# Das Spiel hat seinen Status abgeräumt: Musik gleich wieder zeigen.
		_shown = ""
		# Erst nachdem der Spielstatus abgeräumt ist.
		get_tree().create_timer(2.0).timeout.connect(update)
	)


func wanted() -> bool:
	return Config.is_windows() and bool(Config.get_value("accounts.discord_presence", true)) \
		and bool(Config.get_value("accounts.discord_music_presence", true)) \
		and Voice.client_id() != ""


## Daten für Discord (öffentlich für Tests). {} = nichts zeigen.
static func activity(now: Dictionary, progress: int, unix_now: int) -> Dictionary:
	if now.is_empty() or not bool(now.get("playing", false)) or str(now.get("title", "")) == "":
		return {}
	var start := unix_now - int(progress / 1000.0)
	# Die Texte gehen an Discord, nicht durch ein Label: hier selbst übersetzen (sonst stünde im Englischen „von …“).
	var a := { "type": 2, "details": str(now.title),
			"state": str(TranslationServer.translate("von ")) + str(now.get("artist", "")) if str(now.get("artist", "")) != "" else str(TranslationServer.translate("Musik")),
			"start": start }
	var dur := int(now.get("duration", 0))
	if dur > 0:
		a["end"] = start + int(dur / 1000.0)
	var art := str(now.get("art", ""))
	if art.begins_with("https://"):
		a["image"] = art
		a["large_text"] = str(now.get("album", now.title))
	var uri := str(now.get("uri", ""))
	if uri.begins_with("spotify:track:"):
		a["buttons"] = [{ "label": str(TranslationServer.translate("Auf Spotify mithören")), "url": "https://open.spotify.com/track/" + uri.get_slice(":", 2) }]
	return a


## Muss der Status neu an Discord? Bei einem anderen Titel oder wenn im Titel gesprungen wurde.
static func neu_setzen(titel: String, start: int, gezeigt: String, gezeigt_start: int) -> bool:
	return titel != gezeigt or absi(start - gezeigt_start) > SPRUNG_S


func update() -> void:
	if Launcher.in_game or not wanted():
		return
	var a := activity(Music.now, Music.progress_ms(), int(Time.get_unix_time_from_system()))
	if a.is_empty():
		if _shown != "":
			_shown = ""
			Helper.run("presence-clear")
		return
	# Nur bei neuem Titel oder Sprung neu setzen (Discord drosselt häufige Änderungen).
	var key := str(Music.now.get("uri", Music.now.get("title", "")))
	if not neu_setzen(key, int(a.start), _shown, _shown_start):
		return
	_shown = key
	_shown_start = int(a.start)
	a["client_id"] = Voice.client_id()
	if Voice.builtin():
		a["small"] = Voice.PRESENCE_SMALL
	Helper.run("presence", a)

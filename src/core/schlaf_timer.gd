extends Node
## Schlaf-Timer: „in 30 Minuten aus“ oder „nach dieser Folge“. Ist es so weit, halten Video und
## Musik an und Uzai geht in den Ruhemodus (rest.gd) – beim Aufwachen läuft nichts von selbst
## weiter, das Video wartet an seiner Stelle. Am Ende einer Folge startet keine nächste.
## Eine Minute vorher eine leise Mitteilung; ein Druck auf die Kachel stellt neu.
## Stellen: Schnellmenü (Kachel „Schlaf-Timer“, A schaltet weiter), Ausschalten-Menü, im Video
## Y → Wiedergabe. Gilt nur für diese Sitzung (kein Einstellungs-Schlüssel).
## Die Logik ist statisch und ohne Fenster testbar (tests/logic_komfort.gd).

## Reihenfolge der Kachel: aus, Minuten, dann „Ende“ (nur, solange ein Video läuft).
const STUFEN := ["", "15", "30", "60", "90", "ende"]
const WARN_S := 60
const TICK_S := 5.0

var rest: Node                 ## Ruhemodus (src/core/rest.gd), dem der Timer gehört
var stufe := ""                ## "" aus, Minuten als Text oder "ende"
var bis := 0                   ## Unix-Zeit, zu der es so weit ist (nur bei Minuten)
var _gewarnt := false
var _selbst := false           ## das Video hält gerade wegen des Timers an (kein Abbrechen)


func _ready() -> void:
	var t := Timer.new()
	t.wait_time = TICK_S
	t.timeout.connect(_tick)
	add_child(t)
	t.start()
	Video.reached_end.connect(_on_end)
	Video.stopped.connect(_on_stopped)


# --- Logik (statisch) -----------------------------------------------------------------------

## Nächste Stufe für die Kachel; „Ende“ nur mit laufendem Video.
static func naechste(s: String, video: bool) -> String:
	var liste: Array = STUFEN if video else STUFEN.filter(func(x: String) -> bool: return x != "ende")
	var i := liste.find(s)
	return str(liste[(i + 1) % liste.size()]) if i >= 0 else str(liste[1])


static func gueltig(s: String) -> bool:
	return STUFEN.has(s)


## Ende der Frist für eine Minuten-Stufe (sonst 0).
static func frist(s: String, now: int) -> int:
	return now + int(s) * 60 if s.is_valid_int() and int(s) > 0 else 0


## Verbleibende Minuten, aufgerundet (1 bis zum Schluss).
static func rest_min(ende: int, now: int) -> int:
	return maxi(0, ceili((ende - now) / 60.0))


static func faellig(s: String, ende: int, now: int) -> bool:
	return s.is_valid_int() and ende > 0 and now >= ende


static func warnen(s: String, ende: int, now: int, gewarnt: bool) -> bool:
	return s.is_valid_int() and not gewarnt and ende > 0 and now < ende and ende - now <= WARN_S


## „Nach dieser Folge“ (Serie), „Nach diesem Film“, „Nach diesem Video“ (YouTube, Twitch).
static func ende_text(art: String) -> String:
	match art:
		"series":
			return "Nach dieser Folge"
		"movie":
			return "Nach diesem Film"
	return "Nach diesem Video"


## Zustand für Kachel und Menü: "" (aus), „noch 12 Min.“ oder der Ende-Text.
static func zustand(s: String, ende: int, now: int, art: String) -> String:
	if s == "":
		return ""
	if s == "ende":
		return ende_text(art)
	return TranslationServer.translate("noch %d Min.") % rest_min(ende, now)


## Auswahl für Menüs: [Wert, Name]; „Ende“ nur mit laufendem Video.
static func optionen(video: bool, art: String) -> Array:
	var out: Array = [["", "Aus"], ["15", "15 Min."], ["30", "30 Min."], ["60", "1 Std."], ["90", "1,5 Std."]]
	if video:
		out.append(["ende", ende_text(art)])
	return out


# --- Laufzeit ---------------------------------------------------------------------------------

## Was gerade läuft: series, movie oder video ("" ohne Video).
static func art() -> String:
	if not Video.active:
		return ""
	if Video.video.has("movies"):
		var m: Variant = Movies.now_playing().get("meta")
		return "series" if m is Dictionary and str((m as Dictionary).get("type", "")) == "series" else "movie"
	return "video"


func text() -> String:
	return zustand(stufe, bis, int(Time.get_unix_time_from_system()), art())


func an() -> bool:
	return stufe != ""


## Kachel: eine Stufe weiter.
func weiter() -> void:
	setzen(naechste(stufe, Video.active))


func setzen(s: String) -> void:
	if not gueltig(s) or (s == "ende" and not Video.active):
		s = ""
	var war := stufe
	stufe = s
	bis = frist(s, int(Time.get_unix_time_from_system()))
	_gewarnt = false
	if s == "" and war == "":
		return
	if s == "":
		Toasts.show_toast("Schlaf-Timer aus", "", "clock", { "quiet": true, "ms": 1800, "overlay": true })
	else:
		var wann := ende_text(art()) if s == "ende" else TranslationServer.translate("Ruhemodus in %d Min.") % int(s)
		Toasts.show_toast("Schlaf-Timer", wann, "clock", { "quiet": true, "ms": 2200, "overlay": true })
	Helper.hlog("Schlaf-Timer: %s" % (s if s != "" else "aus"))


func _tick() -> void:
	if stufe == "" or stufe == "ende":
		return
	# Schon im Ruhemodus (von Hand, Ruhebildschirm): der Timer hat sich erledigt.
	if rest and bool(rest.get("active")):
		stufe = ""
		bis = 0
		return
	var now := int(Time.get_unix_time_from_system())
	if warnen(stufe, bis, now, _gewarnt):
		_gewarnt = true
		Toasts.show_toast("Gleich Ruhemodus", "In einer Minute. Schnellmenü → Schlaf-Timer stellt neu.", "clock",
				{ "quiet": true, "sound": "notify", "ms": 6000, "overlay": true })
	elif faellig(stufe, bis, now):
		einschlafen()


## Ende eines Videos oder einer Folge: Movies hat die nächste Folge schon geplant – absagen.
func _on_end() -> void:
	if stufe != "ende":
		return
	Movies.cancel_autoplay()
	einschlafen(true)


## Video von Hand beendet: „nach diesem Video“ gilt nicht für das nächste.
func _on_stopped() -> void:
	if stufe == "ende" and not _selbst:
		stufe = ""


## So weit: Video anhalten (am Ende: beenden, die Stelle ist gemerkt), Musik anhalten, Ruhemodus.
func einschlafen(am_ende := false) -> void:
	stufe = ""
	bis = 0
	_selbst = true
	Helper.hlog("Schlaf-Timer: Ruhemodus")
	if Video.active:
		if am_ende:
			await Video.stop()
		elif not Video.paused:
			Video.set_pause(true)
	if bool(Music.now.get("playing", false)):
		Music.play_pause(false)
	_selbst = false
	if rest and rest.has_method("enter"):
		rest.enter("schlaf-timer")

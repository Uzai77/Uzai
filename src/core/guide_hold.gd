extends RefCounted
## Guide button, short or long press (item 21), as on Xbox and PlayStation: a short press opens the Guide,
## holding it opens the quick menu (screenshot, clip, microphone, rest mode, quit game).
## The Guide opens on press, not on release. Previously a press waited for the release so that holding
## would not show the Guide first; but a normal press lasts 80 to 200 ms, so the Guide opened noticeably
## late every time. Now this class only records the press: if the button stays down for MENU_MS, it
## reports "menu" and the Guide that just opened makes way for the quick menu (main_guide.gd).
## The chord View + Start, Start alone and Uzai itself have no hold action.
## Setting controller.guide_hold: "menu" (default), "rest" (hold = rest mode, rest.gd) or
## "aus". No state outside this class, which keeps it testable (tests/logic_guidetasten.gd); main holds
## one instance.

const MODES := ["menu", "rest", "aus"]
## So lange halten fürs Schnellmenü – ein normaler Druck dauert 80–200 ms.
const MENU_MS := 500
## So lange halten für den Ruhemodus (Einstellung „Ruhemodus“, wie bisher).
const REST_MS := 1000
## Der Helfer meldet weder Loslassen noch Halten (neu gestartet, Controller weg): dann ist der Druck vorbei.
const GRACE_MS := 1500

var waiting := false   ## ein Druck läuft: gehalten wird er zum Schnellmenü
var src := ""          ## "pad" (Godot: Guide-Taste, Taste G/Pos1) oder "helper" (XInput im Hintergrund)
var at := 0            ## wann gedrückt (ms)


static func mode() -> String:
	var m := str(Config.get_value("controller.guide_hold", "menu"))
	return m if m in MODES else "menu"


## Haltezeit für den Controller-Wächter des Helfers (0 = er meldet kein Halten).
static func hold_ms(m: String) -> int:
	match m:
		"menu": return MENU_MS
		"rest": return REST_MS
	return 0


## Ein Druck der Guide-Taste, der den Guide öffnet: merken, ob er zum Halten werden kann. Nur die
## echte Guide-Taste und nur mit Schnellmenü. true: ab jetzt entscheiden tick bzw. helper.
func druck(source: String, now: int, m := "") -> bool:
	if (m if m != "" else mode()) != "menu" or not (source in ["pad", "helper"]):
		return false
	waiting = true
	src = source
	at = now
	return true


## Ein laufender Druck, aus Godots Sicht: held = die Taste ist noch unten (nur bei src "pad"; beim
## Helfer zählen seine Meldungen). "menu" (MENU_MS gehalten) oder "" (nichts zu tun).
func tick(now: int, held: bool) -> String:
	if not waiting:
		return ""
	if src == "pad":
		if not held:
			return _done("")
		if now - at >= MENU_MS:
			return _done("menu")
		return ""
	if now - at >= MENU_MS + GRACE_MS:
		return _done("")
	return ""


## Meldung des Helfers: "guide-up" (losgelassen: der Guide bleibt) oder "guide-hold" (MENU_MS
## gehalten, er misst selbst – genauer als Uzai mit 12 Bildern pro Sekunde im Spiel).
func helper(ev: String) -> String:
	if not waiting or src != "helper":
		return ""
	match ev:
		"guide-up": return _done("")
		"guide-hold": return _done("menu")
	return ""


## Guide halten + X (Clip): kein Schnellmenü.
func cancel() -> void:
	waiting = false


func _done(what: String) -> String:
	waiting = false
	return what

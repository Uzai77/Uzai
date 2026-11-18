extends RefCounted
## Bildzeiten einer Animation (Start, Ausschalten, Startanimation je System) messen und einmal ins
## Protokoll schreiben (logs/godot.log): wie viele Bilder, das längste mit seinem Zeitpunkt in der
## Animation und wie viele über ZAEHLT_MS lagen. So lässt sich am PC nachlesen, ob und wo es
## ruckelt („Startanimation: 140 Bilder, längstes 41 ms bei 0,52 s, 3 über 25 ms“).

## Ab dieser Bildzeit gilt ein Bild als Ruckler (bei 60 Hz anderthalb Bilder).
const ZAEHLT_MS := 25.0

var bilder := 0
var laengstes_ms := 0.0
var laengstes_bei := 0.0          ## Zeitpunkt in der Animation (s), an dem das längste Bild endete
var ruckler := 0
var _letzt_us := -1


## Ein Bild ist gezeichnet; t ist der Zeitpunkt in der Animation. Das erste Bild misst nur den Anfang.
func bild(t: float, jetzt_us := -1) -> void:
	var now := jetzt_us if jetzt_us >= 0 else Time.get_ticks_usec()
	if _letzt_us >= 0:
		var ms := (now - _letzt_us) / 1000.0
		bilder += 1
		if ms > laengstes_ms:
			laengstes_ms = ms
			laengstes_bei = t
		if ms > ZAEHLT_MS:
			ruckler += 1
	_letzt_us = now


func bericht(name: String) -> String:
	if bilder == 0:
		return "%s: keine Bilder gemessen" % name
	return "%s: %d Bilder, längstes %d ms bei %.2f s, %d über %d ms" % [name, bilder, roundi(laengstes_ms), laengstes_bei,
		ruckler, roundi(ZAEHLT_MS)]


## Einmal ins Protokoll (print landet in logs/godot.log).
func melden(name: String) -> void:
	print(bericht(name))

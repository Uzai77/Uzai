extends RefCounted
## Spiel im Fernseher (Punkt 131, Stufe 2): Ein Spiel, das du im Zimmer einlegst (oder A am Fernseher
## über einem laufenden Spiel), geht fokussiert ins Spiel: Die Kamera fährt in den Bildschirm des
## Fernsehers, bis er das ganze Bild füllt, und genau dort liegt dann das Spiel randlos vorn – mit
## Controller und Tastatur, ohne Schnitt. Uzai ruht dahinter, das Zimmer wartet unsichtbar (es zeichnet
## nichts, zimmer_basis.gd ruhen). Die Guide-Taste (der Helfer liest sie im Hintergrund) fährt sofort
## zurück ins Zimmer, ohne Guide; erst der nächste Druck öffnet ihn dort. Hier stehen nur Zustände und
## Übergänge (ohne Fenster, prüfbar: tests/logic_fernsehspiel.gd); die Fenster schaltet main
## (main_ebenen.gd, main_fenster.gd), die Kamera das Zimmer (zimmer_ansehen.gd).
##
##   ""           kein Spiel im Fernseher
##   "startet"    im Zimmer eingelegt, das Spielfenster kommt noch (Uzai deckt vorn ab, die Kamera vor
##                dem Fernseher); ist es da, fährt die Kamera hinein und es geht ins Vollbild
##   "zimmer"     im Zimmer: du läufst, das Spiel läuft weiter und der Fernseher zeigt es live
##                (spielbild.gd, Windows Graphics Capture); Uzai vorn mit dem Fokus, der Controller
##                steuert die Figur. Emulatoren laufen ohne Fokus weiter und lesen den Controller dann
##                nicht (src/core/emu_hintergrund.gd, wo sie es können); wer ihn auch im Hintergrund liest
##                (PCSX2, yuzu & Co.), hält an, bis du wieder spielst. Auch: Guide › Dein Zimmer im Spiel.
##   "vollbild"   fokussiert: das Spiel liegt randlos vorn und hat den Controller, Uzai ruht
##
## Nur im Vollbild hat das Spiel Fokus und Controller. Überall sonst im Zimmer – laufen, bauen, Foto,
## Menüs – hat Uzai den Fokus: Launcher.focus_game holt das Spiel dann nie nach vorn (fokus_gesperrt),
## und legt sich das Spiel selbst nach vorn, nimmt Uzai den Fokus zurück (main_fenster.gd
## _tv_zimmer_wache). Der Ton kommt dann aus dem Fernseher (raumton.gd).
## Grenze: XInput liest jeder Prozess unabhängig vom Fokus. Ein Spiel, das den Controller auch ohne
## Fokus abfragt, sieht deine Eingaben weiter – das lässt sich ohne Treiber oder Eingriff ins Spiel
## nicht verhindern, und beides tut Uzai nicht. Die meisten Spiele (SDL, Unity, viele Unreal-Spiele)
## und die Emulatoren mit passender Einstellung (src/core/emu_hintergrund.gd) hören ohne Fokus weg.

const ZUSTAENDE := ["", "startet", "zimmer", "vollbild"]
## Spiel im Fernseher (main_fenster.gd _tv), genau die Wechsel von weiter(): einlegen, ins Vollbild, aufstehen
## (auch: Guide › Dein Zimmer über dem Spiel), Spielende von überall.
const ZUSTAENDE_TV := { "*": [""], "": ["startet", "zimmer"], "startet": ["vollbild"], "zimmer": ["vollbild"], "vollbild": ["zimmer"] }
## So oft schaut main nach, ob das Spiel sich im Zimmer nach vorn gelegt hat (main_fenster.gd).
const PRUEF_S := 1.0


## Nächster Zustand nach einem Ereignis. Unpassende Ereignisse ändern nichts.
##   einlegen   im Zimmer gestartet
##   vollbild   die Kamera ist im Fernseher angekommen: das Spiel nach vorn (beim Start, aus dem Zimmer)
##   aufstehen  zurück ins Zimmer (Guide-Taste im Vollbild, Guide › Dein Zimmer über dem Spiel)
##   ende       Spiel aus (auch: Start ging nicht)
static func weiter(z: String, e: String) -> String:
	if not (z in ZUSTAENDE):
		z = ""
	match e:
		"ende":
			return ""
		"einlegen":
			return "startet" if z == "" else z
		"vollbild":
			return "vollbild" if z in ["startet", "zimmer"] else z
		"aufstehen":
			return "zimmer" if z in ["", "vollbild"] else z
	return z


## Was ein Druck der Guide-Taste beim Spiel im Zimmer bewirkt: im Vollbild „aufstehen“ – gleich beim
## Drücken zurück ins Zimmer, ohne Halten und ohne dass der Guide aufgeht; sonst „guide“.
static func guide_taste(z: String) -> String:
	return "aufstehen" if z == "vollbild" else "guide"


## Darf das Spiel in diesem Zustand nach vorn (Fokus und mit ihm Controller und Tastatur)? Nicht,
## solange du im Zimmer läufst – dann steuert der Controller die Figur (Launcher.focus_game prüft das).
static func fokus_gesperrt(z: String) -> bool:
	return z == "zimmer"


## Klingt das Spiel in diesem Zustand aus dem Fernseher im Zimmer (raumton.gd)? Nur im Vollbild normal.
static func ton_im_raum(z: String) -> bool:
	return z != "vollbild"


## Liegt Uzai in diesem Zustand sichtbar über dem Spiel (dann braucht es keinen Vorhang)?
static func uzai_vorn(z: String) -> bool:
	return z in ["startet", "zimmer"]


## Schauen alle im Zimmer aufs Spiel? Du im Vollbild und jeder Gast ebenso (gaeste: je { fokus }).
## Nur dann sieht niemand das Zimmer, und es darf mit weniger Bildern laufen (zimmer_basis.gd
## ruhe_fps). Ein Gast ohne Angabe zählt als im Zimmer unterwegs: Zimmer online sendet keinen Fokus
## (netz_protokoll.gd kennt die Meldung nicht) – mit Gästen läuft das Zimmer darum immer mit voller Rate.
static func alle_fokussiert(z: String, gaeste: Array) -> bool:
	if z != "vollbild":
		return false
	for g in gaeste:
		if not (g is Dictionary and bool((g as Dictionary).get("fokus", false))):
			return false
	return true

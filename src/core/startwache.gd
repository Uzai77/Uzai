extends RefCounted
## Nach dem Start gehört Uzai nach vorn – und der Controller muss gehen, ohne dass man erst die Guide-Taste drückt.
##
## Uzai nimmt den Controller nur an, wenn sein Fenster vorn ist (Nav._pad_allowed). Meldungen vom PC (0.16.55 und
## wieder 0.16.62): „Wenn man Uzai startet, kann man sich nicht bewegen, man muss kurz Guide drücken.“ Die erste
## Abhilfe (0.16.56) sah nur in den ersten 7 Sekunden viermal nach und hörte beim ersten „vorn“ auf. Das reicht
## nicht, wenn
##   – der Helfer später bereit ist als das (ohne ihn lässt Windows ein Fenster im Hintergrund nicht vor),
##   – Uzai erst vorn ist und ein Programm, das beim Start mit anläuft, sich danach davorsetzt,
##   – Windows Uzais Fenster als das vordere führt, Godot davon aber nichts erfahren hat.
## Welche davon am PC zutrifft, ist nicht bekannt (logs/start.log fehlt bisher). Darum passt die Wache jetzt bis
## zum ersten angenommenen Tastendruck auf, höchstens DAUER_MS, und schreibt mit, was sie sieht.
##
## Hier steht nur die Entscheidung (ohne Fenster prüfbar, tests/logic_startwache.gd); der Ablauf ist
## main._start_vorn().

const Fremd := preload("res://src/core/fremd.gd")

const DAUER_MS := 60000        ## so lange passt die Wache nach dem Start auf
const TAKT_S := 1.0            ## so oft sieht sie nach
const HOLEN_MAX := 8           ## so oft holt sie Uzai höchstens nach vorn (kein Tauziehen mit einem anderen Programm)
const NUTZER_MS := 1500        ## Maus oder Tastatur vor so kurzer Zeit benutzt: Der Nutzer hat selbst gewechselt
const SCHONFRIST_MS := 4000    ## in den ersten Sekunden zählt das nicht (der Klick, der Uzai gestartet hat)
const GILT_MS := 2500          ## so lange gilt „Windows führt Uzai als vorn“ für den Controller weiter


## Was tun, solange Godot meldet, dass Uzais Fenster nicht vorn ist?
##   "gilt"   Windows führt Uzais Fenster als das vordere: Der Controller zählt trotzdem (Nav.vorn_gilt).
##   "holen"  Uzai nach vorn holen.
##   "warten" nichts tun, weiter beobachten (der Helfer ist noch nicht da, und Uzai war schon einmal vorn).
##   "ende"   aufhören: Der Nutzer bedient gerade etwas anderes, oder es wurde oft genug versucht.
## lage: alter_ms (seit dem Start), hatte (Uzai war schon einmal vorn), geholt (bisherige Versuche), helfer (antwortet),
##   idle_ms (seit der letzten Maus- oder Tastatureingabe am PC, -1 unbekannt), fg_eigen (Windows nennt Uzais Fenster
##   als das vordere), taste (am Controller wurde gedrückt, während Uzai nicht vorn war).
static func schritt(lage: Dictionary) -> String:
	if Fremd.ja(lage.get("fg_eigen")):
		return "gilt"
	if Fremd.zahl(lage.get("geholt")) >= HOLEN_MAX:
		return "ende"
	var taste := Fremd.ja(lage.get("taste"))
	var hatte := Fremd.ja(lage.get("hatte"))
	var helfer := Fremd.ja(lage.get("helfer"))
	var idle := Fremd.zahl(lage.get("idle_ms"), -1)
	# Wer am Controller drückt, will Uzai bedienen – gleich, was sonst war.
	if taste:
		return "holen"
	var eben_benutzt := helfer and idle >= 0 and idle < NUTZER_MS
	if eben_benutzt and (hatte or Fremd.zahl(lage.get("alter_ms")) > SCHONFRIST_MS):
		return "ende"
	if not hatte:
		return "holen"
	# Uzai war vorn und ist es nicht mehr: nur zurückholen, wenn sicher niemand Maus oder Tastatur benutzt hat.
	if helfer and idle >= NUTZER_MS:
		return "holen"
	return "warten"


## Eine Zeile fürs Protokoll, wer vorn liegt (aus der Antwort des Helfers auf window-state).
static func vorn_text(st: Dictionary, eigen_hwnd: int, eigen_pid: int) -> String:
	if st.is_empty():
		return "unbekannt (Helfer noch nicht bereit)"
	var wer := ""
	if Fremd.zahl(st.get("fg_hwnd")) == eigen_hwnd and eigen_hwnd != 0:
		wer = ", Uzais eigenes Fenster"
	elif Fremd.zahl(st.get("fg_pid")) == eigen_pid:
		wer = ", ein Fenster von Uzai"
	return "„%s“ (%s%s)" % [Fremd.text(st.get("fg_title"), "", 40), Fremd.text(st.get("fg_class")), wer]


## Fürs Protokoll: Zeit seit der letzten Maus- oder Tastatureingabe am PC („4200 ms“, „?“ wenn unbekannt).
static func idle_text(st: Dictionary) -> String:
	var idle := Fremd.zahl(st.get("idle_ms"), -1)
	return ("%d ms" % idle) if idle >= 0 else "?"

extends RefCounted
## Vorhang zwischen Uzai und dem Spiel: Beim Spielstart und Spielende sah man früher kurz Windows –
## Desktop und Taskleiste, während das Spiel noch nicht gezeichnet hatte bzw. bis Uzai das Ende
## bemerkte (bis zu fünf Sekunden). Jetzt deckt ein randloses, oberstes Fenster des Helfers ohne
## Taskleisten-Eintrag (UzEbenen in helper/uzai-helper.ps1) diese Übergänge ab:
##   start    Uzai gibt an das Spiel ab: schwarz, bis ein Fenster vorn den Bildschirm deckt
##   starter  … aber zuerst kam ein Starter (Steam-Dialog, Epic, Launcher des Spiels): länger, bis das
##            Spiel selbst ein Fenster hat (dann „start“) – früher ging er nach Sekunden, und man sah
##            den Desktop, während der Launcher noch lud
##   warten   ein Fenster wartet beim Start auf dich (Uzai gibt den Vorrang ab): in Uzais Grundfarbe
##   wache    solange das Spiel läuft: verschwindet sein Fenster, zieht der Helfer sofort zu
##   beenden  Guide → Beenden bei Emulatoren und vor jedem harten Beenden: schwarz, solange es sich
##            schließt – auch über dem Spiel im Vollbild (immer), seine Rückfrage ist schon beantwortet
##   schliessen  das Spielfenster ist weg, das Spiel aber noch nicht zu (speichert, fährt herunter,
##            Uzai beendet es gerade): schwarz, ein Loch nur um Fenster des Spiels (seine Rückfrage) –
##            nie um ein fremdes (Browser, Explorer, Steam), das Windows danach nach vorn legt. Früher
##            wurde daraus nach 3 s der Start-Vorhang mit Loch um jedes Fenster: man sah kurz Windows.
##   ende     Uzai kommt zurück: schwarz, bis Uzai gezeichnet hat und vorn ist
## Warum es trotzdem kurz Windows zu sehen gab (0.10.1) und was dagegen hilft:
##   - Die Aufträge liefen über den Hauptweg des Helfers (der erste kam, bevor der schnelle bereit
##     war) und warteten dort hinter Discord, Musik und der Prozesssuche: Uzai gab nach einer Sekunde
##     auf und räumte sich weg, der Vorhang kam später oder gar nicht. Jetzt immer der schnelle Weg
##     (src/core/helper.gd EBENEN).
##   - „an“ kam zurück, bevor der Vorhang gemalt war (der Faden schlief bis zu 120 ms): Uzai wurde
##     durchsichtig und minimierte sich vor einem leeren Bildschirm. Jetzt antwortet der Helfer erst,
##     wenn Windows ihn dargestellt hat (DwmFlush).
##   - Nach jedem Wechsel des Vordergrunds legt Windows die Taskleiste wieder über alles – auch über
##     den Vorhang. Jetzt legt er sich sofort zurück darüber (beim Ende über jedes Fenster).
##   - Ein Fenster, das den Bildschirm zwar deckt, aber noch von Windows versteckt ist oder beim
##     Laden hängt, beendete ihn. Jetzt zählt es erst, wenn es sich zeigt und antwortet.
##   - Ein Ladefenster, das nur kurz vorn liegt (Emulator, Starter), bekam sofort ein Loch; jetzt erst
##     nach LOCH_MS.
##   - Das Spielende sah die Wache erst im nächsten Takt; jetzt meldet Windows es ihr sofort.
## Beim Start bleibt ein fremdes Fenster vorn, das nicht den ganzen Bildschirm deckt (Dialog, Starter,
## Fehlermeldung), ausgespart – der Vorhang verdeckt nie, was auf dich wartet, und holt nichts nach
## vorn. Beim Ende (wache, ende) deckt er alles: gleich kommt ohnehin Uzai. Jeder Auftrag hat eine
## Zeitgrenze; der Helfer gibt den Vorhang auch von selbst frei.
## Hier stehen nur die festen Werte und Aufträge (prüfbar ohne Windows: tests/logic_vorhang.gd).

const START_MS := 8000          ## Übergabe: höchstens so lange schwarz um ein Fenster, das noch kein Vollbild ist
const STARTER_MS := 30000       ## … um einen Starter, bis das Spiel kommt
const LOCH_MS := 700            ## so lange muss ein fremdes Fenster vorn liegen, bis der Vorhang es ausspart
const BEENDEN_MS := 10000       ## Emulator schließt sich: so lange höchstens (danach übernimmt „ende“)
const SCHLIESSEN_MS := 30000    ## Spielfenster weg, Spiel noch nicht zu: so lange höchstens (≥ Launcher.QUIT_MAX_S)
const WARTEN_MS := 120000       ## ein Dialog wartet beim Start: so lange höchstens (wie Launcher.WINDOW_MAX_MS)
const WACHE_MS := 8000          ## Spielfenster weg: so lange höchstens, bis Uzai zurück ist
const ENDE_MS := 4000           ## Rückkehr: spätestens dann geht der Vorhang, auch ohne Uzai vorn
const NICHT_VORN_MS := 1500     ## Rückkehr: gezeichnet, aber Windows gibt Uzai den Fokus nicht – so lange warten
const WEICH_MS := 200           ## Ausblenden
const EIN_MS := 180             ## Einblenden beim Beenden (der Guide geht dabei gerade zu)
const MAX_MS := 180000          ## mehr nimmt der Helfer nicht an
const ANLAESSE := ["start", "starter", "warten", "beenden", "schliessen", "ende"]
const LOCH_PIDS_MAX := 64       ## so viele Prozesse des Spiels nimmt der Helfer fürs Loch an


## Farbe für den Helfer: 0xRRGGBB.
static func farbe(c: Color) -> int:
	return (c.r8 << 16) | (c.g8 << 8) | c.b8


## Auftrag an den Helfer („vorhang“) für einen Anlass; jeder andere Anlass zieht den Vorhang auf.
## hwnd: Uzais Fenster (Bildschirm und eigener Prozess), grund: Uzais Grundfarbe. spiel_pids (nur
## „schliessen“): Prozesse des Spiels – nur ihre Fenster bekommen ein Loch.
static func auftrag(anlass: String, hwnd: int, grund := Color.BLACK, spiel_pids: Array = []) -> Dictionary:
	if hwnd <= 0 or not (anlass in ANLAESSE):
		return { "an": false, "weich_ms": WEICH_MS }
	var ms := START_MS
	var c := Color.BLACK
	if anlass == "warten":
		ms = WARTEN_MS
		c = grund
	elif anlass == "ende":
		ms = ENDE_MS
	elif anlass == "beenden":
		ms = BEENDEN_MS
	elif anlass == "schliessen":
		ms = SCHLIESSEN_MS
	elif anlass == "starter":
		ms = STARTER_MS
	# Beim Warten zeigt das Loch auch Uzai selbst (kommt Uzai nach vorn, ist der Vorhang fertig). Beim
	# Start erst nach LOCH_MS, beim Warten sofort (der Dialog liegt schon drei Sekunden vorn).
	var loch := anlass in ["start", "starter", "warten", "schliessen"]
	# Beim Beenden blendet er weich ein (der Guide geht gleich zu); sonst ist er sofort ganz da – Uzai
	# stellt sein Fenster erst danach um.
	var a := { "an": true, "hwnd": hwnd, "farbe": farbe(c), "max_ms": mini(ms, MAX_MS), "loch": loch, "loch_uzai": anlass == "warten",
		"loch_ms": LOCH_MS if anlass in ["start", "starter", "schliessen"] else 0, "ein_ms": EIN_MS if anlass == "beenden" else 0,
		"immer": anlass == "beenden" }
	if anlass == "schliessen":
		a["loch_pids"] = loch_pids(spiel_pids)
	return a


## Prozessnummern fürs Loch: nur ganze Zahlen über 4 (nie System), ohne Doppelte, höchstens LOCH_PIDS_MAX.
static func loch_pids(pids: Array) -> Array:
	var out: Array = []
	for p in pids:
		if (p is int or p is float) and int(p) > 4 and not out.has(int(p)) and out.size() < LOCH_PIDS_MAX:
			out.append(int(p))
	return out


## Die Wache hat zugezogen (Spielfenster weg). Was jetzt? ms: seit dem Auslösen, beenden: Uzai beendet
## das Spiel gerade, fg_game/voll: das Vordergrundfenster gehört dem Spiel (bzw. deckt im Vollbild schon
## so lange den Bildschirm), gedeckt: „schliessen“ steht schon.
##   "folgen"      das Spiel zeigt wieder ein Fenster – die Wache folgt ihm, der Vorhang geht von selbst
##   "schliessen"  bis zum Ende schwarz, Loch nur um Fenster des Spiels
##   ""            weiter nachsehen
static func nach_wache(ms: int, beenden: bool, fg_game: bool, voll: int, gedeckt: bool, laeuft_ms: int) -> String:
	if fg_game and (voll >= 2 or gedeckt):
		return "folgen"
	if not gedeckt and (beenden or ms >= laeuft_ms):
		return "schliessen"
	return ""


## Wache für das laufende Spiel („vorhang-wache“); ohne Spielfenster aus.
static func wache(hwnd: int, spiel: int) -> Dictionary:
	if hwnd <= 0 or spiel <= 0:
		return { "an": false }
	return { "an": true, "hwnd": hwnd, "spiel": spiel, "farbe": 0, "max_ms": WACHE_MS }


## Darf der Vorhang nach der Rückkehr weg? Erst wenn Uzai mindestens zwei Bilder gezeichnet hat, seit
## sein Fenster wieder offen ist, und vorn ist (oder es nach NICHT_VORN_MS nicht mehr wird) –
## spätestens nach ENDE_MS.
static func darf_weg(bilder: int, vorn: bool, ms: int) -> bool:
	return (bilder >= 2 and (vorn or ms >= NICHT_VORN_MS)) or ms >= ENDE_MS

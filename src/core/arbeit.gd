extends RefCounted
## Hintergrundarbeit an einer Stelle: Alles, was Uzai neben dem Bild erledigt (Symbole rastern,
## Bilder dekodieren, Ordner durchsuchen, große Antworten lesen), läuft über diese Datei.
##
##   Arbeit.los(_dekodieren.bind(pfad))                    # starten; das Ergebnis meldet der Auftrag selbst
##   var liste: Variant = await Arbeit.ergebnis(_suchen.bind(ordner), Arbeit.LANG)
##   var a := Arbeit.auftrag(_einlesen.bind(stand), Arbeit.LANG)   # nebenbei Fortschritt zeigen: a.fertig, a.wert
##
## Drei Arten, damit Kleines nie hinter Großem wartet. Jede hat ihre eigene Spur:
##   SOFORT  winzig und sichtbar (ein Symbol)
##   KURZ    Bruchteile einer Sekunde (Bild dekodieren, JSON lesen)
##   LANG    Sekunden bis Minuten (Ordner durchsuchen, Größe messen)
##
## Warum nicht WorkerThreadPool.add_task direkt: Godot 4.5 bedient Aufgaben ohne Vorrang auf vier
## Kernen mit einem einzigen Faden, streng der Reihe nach, und lädt über dieselbe Schlange selbst
## im Hintergrund (ResourceLoader.load_threaded_…). Ein Ordner-Scan hielt so jedes Symbol und jedes
## Cover auf, und das Bild stand, sobald eine Ebene geholt wurde. Wartet beim Beenden noch eine
## solche Aufgabe, bleibt Godot für immer stehen; eine nie abgeholte Aufgabe mit Lambda stürzt beim
## Beenden ab. Darum führt Uzai eigene Schlangen: Im Pool laufen nur „Läufer“ (mit Vorrang, feste
## Funktion). Sie holen die Aufträge von hier, und jeder Läufer wird abgeholt.
##
## Beenden: Sobald die Wurzel den Baum verlässt (alles andere hat dann gespeichert), verfallen
## wartende Aufträge, und wer auf ein Ergebnis wartet, wird nicht mehr geweckt. Laufende Aufträge
## bekommen WARTEN_MS; lange Schleifen fragen dafür Arbeit.endet ab.
##
## Vorladen (vorladen/geladen): immer nur eine Ressource zugleich in Godots Schlange. So wartet
## geladen() höchstens auf diese eine, und beim Beenden steht dort nichts an.
##
## Geprüft in tests/logic_arbeit.gd.

const SOFORT := 0
const KURZ := 1
const LANG := 2

## So lange dürfen laufende Aufträge beim Beenden noch brauchen.
const WARTEN_MS := 3000

## Uzai beendet sich. Lange Schleifen in Aufträgen hören auf, sobald das wahr ist.
static var endet := false

static var _schloss := Mutex.new()
static var _wartend: Array = [[], [], []]   ## je Art die wartenden Aufträge, der Reihe nach
static var _laeufer: Array[int] = [0, 0, 0] ## laufende Läufer je Spur
static var _grenze: Array[int] = []         ## höchstens so viele Läufer je Spur
static var _ids: Array[int] = []            ## Aufgaben der Läufer im Pool, noch nicht abgeholt
static var _angemeldet := false
static var _faeden: Array = []              ## Dauerfäden: je [Thread, wecken]

static var _lade_schlange: Array[String] = []
static var _lade_pfad := ""                 ## diese eine Ressource lädt Godot gerade im Hintergrund
static var _lade_laeuft := false
static var _geladen := {}                   ## Pfad → Ressource (hält sie fest)


## Ein Auftrag. fertig und wert ändern sich nur im Hauptfaden.
class Auftrag extends RefCounted:
	## Im Hauptfaden, sobald fertig wahr ist.
	signal erledigt
	var fn: Callable
	var wert: Variant = null
	var fertig := false
	var melden := false


## Startet fn im Hintergrund. Ein Ergebnis meldet der Auftrag selbst (call_deferred).
static func los(fn: Callable, art: int = KURZ) -> void:
	var a := Auftrag.new()
	a.fn = fn
	_einreihen(a, art)


## Startet fn im Hintergrund und gibt den Auftrag zurück: a.fertig wird im Hauptfaden wahr, a.wert
## ist dann der Rückgabewert von fn. Für alle, die beim Warten etwas zeigen.
static func auftrag(fn: Callable, art: int = KURZ) -> Auftrag:
	var a := Auftrag.new()
	a.fn = fn
	a.melden = true
	_einreihen(a, art)
	return a


## Führt fn im Hintergrund aus und gibt den Rückgabewert zurück. Mit await, nur im Hauptfaden.
## Bricht fn mit einem Fehler ab oder lebt sein Ziel nicht mehr, kommt null zurück: nie ein Warten
## ohne Ende.
static func ergebnis(fn: Callable, art: int = KURZ) -> Variant:
	var a := auftrag(fn, art)
	if not a.fertig:
		await a.erledigt
	return a.wert


## Ein eigener Faden für eine Schleife, die läuft, solange Uzai läuft (alle Netz-Abrufe, src/core/abruf.gd). Nicht
## für Aufträge: Die gehören in die Spuren oben. Die Schleife fragt Arbeit.endet ab und darf nie blockieren;
## wecken holt sie aus ihrem Warten. beenden() wartet auf sie wie auf die Läufer.
static func dauerfaden(schleife: Callable, wecken: Callable) -> bool:
	var t := Thread.new()
	_schloss.lock()
	var geht := not endet
	if geht:
		_faeden.append([t, wecken])
	var anmelden := not _angemeldet
	_schloss.unlock()
	if not geht:
		return false
	t.start(schleife)
	if anmelden:
		if OS.get_thread_caller_id() == OS.get_main_thread_id():
			_anmelden()
		else:
			_anmelden.call_deferred()
	return true


## Wartende Aufträge und laufende Läufer zusammen: 0 heißt Ruhe.
static func offen() -> int:
	_schloss.lock()
	var n := _laeufer[SOFORT] + _laeufer[KURZ] + _laeufer[LANG]
	for liste: Array in _wartend:
		n += liste.size()
	_schloss.unlock()
	return n


## Lädt Skripte und Szenen des Programms nach und nach im Hintergrund, damit geladen() sie sofort hat.
## zuerst: vor allem, was schon wartet (gleich gebraucht, etwa das Zimmer hinter der gewählten Tür).
static func vorladen(pfade: Array, zuerst := false) -> void:
	if endet:
		return
	var neu: Array[String] = []
	for p: Variant in pfade:
		var pfad := str(p)
		if not pfad.begins_with("res://") or _geladen.has(pfad) or pfad == _lade_pfad or neu.has(pfad):
			continue
		if _lade_schlange.has(pfad):
			if not zuerst:
				continue
			_lade_schlange.erase(pfad)
		neu.append(pfad)
	if zuerst:
		neu.append_array(_lade_schlange)
		_lade_schlange = neu
	else:
		_lade_schlange.append_array(neu)
	if not _lade_laeuft and not _lade_schlange.is_empty():
		_lade_laeuft = true
		_laden()


## Ist alles davon schon vorgeladen? Wer vorlädt und Zeit hat, wartet darauf (mit eigener Grenze: Eine Datei,
## die sich nicht laden lässt, wird nie fertig).
static func alle_geladen(pfade: Array) -> bool:
	for p: Variant in pfade:
		if not _geladen.has(str(p)):
			return false
	return true


## Die Ressource des Programms unter pfad: sofort, wenn sie vorgeladen ist, sonst lädt sie jetzt.
static func geladen(pfad: String) -> Resource:
	if _geladen.has(pfad):
		return _geladen[pfad]
	if not pfad.begins_with("res://"):
		return null
	var r: Resource = null
	if pfad == _lade_pfad:
		_lade_pfad = ""
		r = ResourceLoader.load_threaded_get(pfad)
	else:
		_lade_schlange.erase(pfad)
		r = load(pfad)
	if r != null:
		_geladen[pfad] = r
	return r


## Schluss: Wartendes verfällt, Laufendes bekommt WARTEN_MS. Kommt von selbst, wenn die Wurzel den
## Baum verlässt, also nach jedem _exit_tree: Es gibt dann nichts mehr zu speichern.
static func beenden() -> void:
	_schloss.lock()
	if endet:
		_schloss.unlock()
		return
	endet = true
	var rest := _wartend
	_wartend = [[], [], []]
	_schloss.unlock()
	# Wartende Aufträge hier im Hauptfaden freigeben (mit ihren Lambdas), solange noch alles lebt.
	rest.clear()
	_lade_schlange.clear()
	if _lade_pfad != "":
		ResourceLoader.load_threaded_get(_lade_pfad)
		_lade_pfad = ""
	_schloss.lock()
	var faeden := _faeden
	_faeden = []
	_schloss.unlock()
	for f: Array in faeden:
		(f[1] as Callable).call()
	var bis := Time.get_ticks_msec() + WARTEN_MS
	while _laeufer_zahl() > 0 or faeden.any(func(f: Array) -> bool: return (f[0] as Thread).is_alive()):
		if Time.get_ticks_msec() > bis:
			# Ein Auftrag steckt fest (etwa in einem Netzlaufwerk, das nicht antwortet). Godot würde
			# beim Aufräumen auf ihn warten und so lange ein stehendes Fenster zeigen. Gespeichert
			# ist alles: den Vorgang hier enden lassen.
			OS.kill(OS.get_process_id())
			return
		OS.delay_msec(2)
	for f: Array in faeden:
		(f[0] as Thread).wait_to_finish()
	_schloss.lock()
	var ids := _ids
	_ids = []
	_schloss.unlock()
	for id: int in ids:
		WorkerThreadPool.wait_for_task_completion(id)


static func _einreihen(a: Auftrag, art: int) -> void:
	var spur := clampi(art, SOFORT, LANG)
	var starten := false
	_schloss.lock()
	if endet:
		_schloss.unlock()
		return
	if _grenze.is_empty():
		# Dem Bild bleibt immer ein Kern: Dekodieren bekommt höchstens die Hälfte, Symbole einen
		# Läufer für sich, lange Arbeit zwei (sie wartet meist auf die Platte).
		var kerne := maxi(OS.get_processor_count(), 1)
		@warning_ignore("integer_division")
		_grenze = [1, clampi(kerne / 2 - 1, 1, 3), 2 if kerne >= 4 else 1]
	(_wartend[spur] as Array).append(a)
	if _laeufer[spur] < _grenze[spur]:
		_laeufer[spur] += 1
		starten = true
	var anmelden := not _angemeldet
	_schloss.unlock()
	if starten:
		var id := WorkerThreadPool.add_task(_laufen.bind(spur), true, "Uzai Hintergrundarbeit")
		_schloss.lock()
		_ids.append(id)
		_schloss.unlock()
	if anmelden:
		if OS.get_thread_caller_id() == OS.get_main_thread_id():
			_anmelden()
		else:
			_anmelden.call_deferred()


## Ein Läufer im Pool: arbeitet seine Spur ab, bis nichts mehr wartet. Abgemeldet wird unter dem
## Schloss, unter dem auch eingereiht wird: Kein Auftrag bleibt ohne Läufer liegen.
static func _laufen(spur: int) -> void:
	while true:
		var a: Auftrag = null
		_schloss.lock()
		if not endet:
			a = _naechster(spur)
		if a == null:
			_laeufer[spur] -= 1
		_schloss.unlock()
		if a == null:
			break
		_ausfuehren(a)
		if a.melden:
			_melden.call_deferred(a)
	_ernten.call_deferred()


## Eigene Funktion, damit ein Fehler beim Aufruf nur sie abbricht und der Läufer weiterarbeitet.
## Lebt das Ziel nicht mehr (Knoten inzwischen entfernt), bleibt der Wert null.
static func _ausfuehren(a: Auftrag) -> void:
	if a.fn.is_valid():
		a.wert = a.fn.call()


## Der nächste Auftrag für einen Läufer dieser Spur. Wer dekodiert, nimmt Symbole zuerst mit.
static func _naechster(spur: int) -> Auftrag:
	if spur == KURZ and not (_wartend[SOFORT] as Array).is_empty():
		return (_wartend[SOFORT] as Array).pop_front()
	var liste: Array = _wartend[spur]
	return null if liste.is_empty() else liste.pop_front()


static func _laeufer_zahl() -> int:
	_schloss.lock()
	var n := _laeufer[SOFORT] + _laeufer[KURZ] + _laeufer[LANG]
	_schloss.unlock()
	return n


static func _melden(a: Auftrag) -> void:
	a.fertig = true
	if not endet:
		a.erledigt.emit()


## Fertige Läufer abholen (Hauptfaden). Wer gerade erst zurückkehrt, ist beim nächsten Mal dran.
static func _ernten() -> void:
	_schloss.lock()
	var ids := _ids
	_ids = []
	_schloss.unlock()
	var offene: Array[int] = []
	for id: int in ids:
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
		else:
			offene.append(id)
	if not offene.is_empty():
		_schloss.lock()
		_ids.append_array(offene)
		_schloss.unlock()


static func _anmelden() -> void:
	var baum := Engine.get_main_loop() as SceneTree
	if _angemeldet or baum == null or baum.root == null:
		return
	_angemeldet = true
	baum.root.tree_exiting.connect(beenden)


static func _laden() -> void:
	var baum := Engine.get_main_loop() as SceneTree
	while baum != null and not endet and not _lade_schlange.is_empty():
		var pfad: String = _lade_schlange.pop_front()
		if ResourceLoader.load_threaded_request(pfad) != OK:
			continue
		_lade_pfad = pfad
		while _lade_pfad == pfad and ResourceLoader.load_threaded_get_status(pfad) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await baum.process_frame
		# Hat geladen() sie inzwischen geholt, ist _lade_pfad schon leer.
		if _lade_pfad == pfad:
			_lade_pfad = ""
			var r := ResourceLoader.load_threaded_get(pfad)
			if r != null:
				_geladen[pfad] = r
	_lade_laeuft = false

extends Node
## Uzai-Browser: der Browser-Kern als eigener Prozess. Standard ist Uzais eigener Chromium über CEF
## (helper/uzai-browser-kern.cs im offiziellen CEF-Bootstrap mit aktiver Sandbox, docs/BROWSER_PLAN.md 2);
## der frühere WebView2-Wirt (helper/uzai-browser-wirt.cs) bleibt nur als ausdrückliche Einstellung
## browser.kern = "webview2" (Notnagel, nie stiller Rückfall). Beide halten die Seite in einem randlosen
## Fenster unter Uzai; Uzai liegt durchsichtig darüber, liest den Controller und zeichnet alles, was man
## sieht (Fokusrahmen, Leiste, Tabs, Menüs, Tastatur). Befehle und Ereignisse gehen als JSON-Zeilen über die
## Standardein- und -ausgabe (browser_protokoll.gd) – kein Anschluss, kein Server, kein Name.
##
## Start (nur Windows): Uzai legt Quellen, Skripte, Filterliste und den Start-Stummel (Prüfsummen hier bzw.
## in browser_kern.gd/browser_filter.gd) neben den Helfer; der Helfer prüft sie noch einmal, übersetzt den
## Kern einmal je Fassung und meldet den Pfad; Uzai startet dann selbst mit fester Argumentliste. Nie mit
## Adminrechten. Fehlt der CEF-Kern noch (erstes Öffnen), kommt „fehler kern“ – die Oberfläche fragt, und
## kern_laden() holt ihn (browser_kern.gd: offizielle Quelle, Prüfsummen, offizieller Installer).
## Ohne Windows (und mit --demo) spielt browser_demo.gd den Kern – über dieselbe Leitung, jede Zeile
## durch dasselbe Schema, damit Proben und Tests das echte Verhalten sehen.
##
## Spotify-Sitzung (spotify = true, src/core/spotify_web.gd): derselbe Kern mit „--uzai-spotify“ – eigener
## Datenordner (spotify-daten), nur Spotify-Seiten, ohne Blocker; meldet den Schlüssel aus den Anfragen der Seite
## (Ereignis „spotify“). Er zählt nicht zur Regel „ein Kern je Uzai“ (anderer Datenordner, kein Profil-Streit) und
## pflegt den Kern nicht (keine Update-Prüfung, kein „gesund“) – das bleibt dem Browser.

const Fremd := preload("res://src/core/fremd.gd")

signal ereignis(e: Dictionary)
signal beendet(grund: String)

const P := preload("res://src/core/browser_protokoll.gd")
const Demo := preload("res://src/core/browser_demo.gd")
const Kern := preload("res://src/core/browser_kern.gd")
const Filter := preload("res://src/core/browser_filter.gd")
const Lauf := preload("res://src/core/browser_kern_lauf.gd")

## Offizielle Dateien aus dem NuGet-Paket Microsoft.Web.WebView2 1.0.4258.31 (assets/browser/webview2/LIZENZ.txt).
const DATEIEN := {
	"Microsoft.Web.WebView2.Core.dll": "d60e6e94245078cb56e44ebd5f360dc04bf18e460136be93bfc4cfca43b98505",
	"WebView2Loader.dll": "3426dcc55fdfb8b5e7ac623cf33b4ccf283fbf68a0c5a65bddfdb4d749a8abee",
}
const QUELLEN := ["uzai-browser-gemeinsam.cs", "uzai-browser-wirt.cs", "uzai-browser-karte.js"]
const ZIEL := "helper/browser"
const EXE_MUSTER := "^[A-Za-z]:\\\\.+\\\\Uzai\\\\browser\\\\bin-[0-9a-f]{12}\\\\uzai-browser\\.exe\\z"
const KERN_EXE_MUSTER := Kern.EXE_MUSTER
static var _RX_EXE := RegEx.create_from_string(EXE_MUSTER)
static var _RX_KERN_EXE := RegEx.create_from_string(KERN_EXE_MUSTER)
static var _RX_PROFIL := RegEx.create_from_string("^[a-z0-9_-]{1,40}\\z")
const MAX_ZEILEN_JE_BILD := 64
const KERNE := ["cef", "webview2"]
## So lange darf der Kern bis „bereit“ brauchen (erster Start: Profil anlegen, GPU) – danach gilt er als hängend.
const START_ZEIT_S := 60.0
const ERR_MAX := 4096
## Rückgabewerte des Kern-Prozesses (= RunWinMain → bootstrap.exe): Kern K…, Stummel S…, Bootstrap/Windows.
const AUSGANG := {
	0: "normal beendet", 2: "K2 Startwerte/Argumente", 3: "K3 Ausnahme im Kern", 4: "K4 Adminrechte", 5: "K5 Skripte fehlen",
	6: "K6 Fenster (oder CEF: falscher Prozesstyp)", 7: "CEF: Daten fehlen", 10: "K10 ohne Sandbox", 11: "K11 libcef",
	12: "K12 Signatur", 13: "K13 API", 14: "K14 CEF-Start", 21: "CEF: Profil in Benutzung", 31: "CEF: Sandbox-Zustand",
	201: "S201 Unterprozess ohne libcef-Pfad", 202: "S202 libcef laden", 203: "S203 API-Hash", 204: "S204 .NET-Laufzeit/Kern-DLL",
	205: "S205 Pfad", 0x80000003: "Abbruch im Bootstrap/CEF (LOG FATAL: Signatur, Ort, Laden)", 0xC0000005: "Zugriffsverletzung",
	0xC000001D: "Abbruch (CHECK)", 0xC0000135: "DLL fehlt", 0xC0000142: "DLL-Initialisierung", 0xC0000409: "Schnellabbruch (CHECK/fail-fast)",
	0xE0434352: ".NET-Ausnahme",
}

var demo := false
var spotify := false            ## Spotify-Sitzung statt Browser (vor starten() setzen)
var bereit := false
var verworfen := 0              ## Befehle, die nicht ins Schema passten (nie geschickt)
var fehler := ""                ## warum der Kern nicht läuft ("" = läuft oder startet)
var kern_fassung := ""          ## was der laufende Kern meldet (bereit.version)
var _pid := 0
var _io: FileAccess
var _err: FileAccess
var _buf := PackedByteArray()
var _sim: RefCounted
var _aus := false
var _gesund_gemeldet := false
var diagnose := ""              ## kurzer Code für den Hinweis („start K6“, „absturz 0x80000003“), lang im Protokoll
var _grund := ""                ## letzter Grund vom Kern („K14 cef_initialize, CEF-Code 21“)
var _gemeldet := false          ## der Kern hat seinen Fehler schon selbst gemeldet
var _seit := 0                  ## Start des Prozesses (ms), 0 = kein Prozess
var _seit_unix := 0
var _err_rest := PackedByteArray()
var _software_versucht := false
var _beenden := false           ## Ende angefordert (Browser zu): ein Ende des Prozesses ist dann normal
var _umzug := false             ## beim Umhängen an die Wurzel (beenden) nicht hart beenden
var _start_ms := 0              ## Start des Prozesses (ms) – für „endete nach … s“
var _zaehler := {}              ## „→springe“ → Anzahl: alle Befehle und Ereignisse der Sitzung, nur die Art
var _zaehler_stand := ""        ## zuletzt protokollierter Stand
var _zaehler_ms := 0
var start_grund := "neue Sitzung"
## Alle Wirte mit lebendem Kern-Prozess: je Uzai höchstens einer (ein neuer wartet, bis der alte weg ist).
static var laufend: Array = []
static var sitzungen := 0
static var doppelt := 0         ## wie oft ein zweiter Kern verhindert wurde (Diagnose, Tests)
var _letzte_zeile := 0          ## letzte Zeile vom Kern (ms) – Z1 erst nach 60 s Stille
var _leitung: Array = []        ## die ersten Befehle (→) und Ereignisse (←), nur die Art, fürs Protokoll
var _verworfene: Array = []     ## Arten verworfener Ereignisse (je einmal protokolliert)
const LEITUNG_MAX := 12
var _leitung_geschrieben := false


func _init() -> void:
	demo = "--demo" in OS.get_cmdline_user_args() or not OS.get_name() == "Windows"


func laeuft() -> bool:
	return not _aus and (_sim != null or (_pid > 0 and OS.is_process_running(_pid)))


## Welcher Kern eingestellt ist: "cef" (Standard) oder "webview2" (ausdrücklicher Notnagel).
static func kern() -> String:
	var k := str(Config.get_value("browser.kern", "cef"))
	return k if k in KERNE else "cef"


## Muss der CEF-Kern erst geladen werden? (Nur echt unter Windows; die Oberfläche fragt dann.)
func kern_noetig() -> bool:
	return not demo and kern() == "cef" and not Kern.bereit()


## Startet den Kern (asynchron; „bereit“ kommt als Ereignis und setzt bereit). Läuft noch ein Kern eines anderen
## Wirts (Browser eben geschlossen, Ende läuft), wartet dieser Start, bis er weg ist – nie zwei Kerne zugleich.
func starten(grund := "neue Sitzung") -> void:
	_aus = false
	_beenden = false
	fehler = ""
	diagnose = ""
	_grund = ""
	_gemeldet = false
	start_grund = grund
	sitzungen += 1
	await _vorgaenger_abwarten()
	if _beenden:
		return
	if not demo:
		Kern.protokoll("Sitzung %d: %s" % [sitzungen, grund])
	if demo:
		_sim = Demo.new()
		_sim.call("verbinden", Callable(self, "_zeile"))
		_start_ms = Time.get_ticks_msec()
		if not spotify:
			laufend.append(self)
		return
	_echt_starten()


## Andere Wirte mit lebendem Kern: höchstens 6 s auf ihr Ende warten, dann hart beenden (Protokoll).
func _vorgaenger_abwarten() -> void:
	if spotify:
		return
	var andere := laufend.filter(func(w: Variant) -> bool: return is_instance_valid(w) and w != self)
	if andere.is_empty():
		return
	doppelt += 1
	if not demo:
		Kern.protokoll("Ein Kern läuft noch (Ende angefordert: %s) – neuer Start wartet" % str(andere.map(func(w: Node) -> bool: return bool(w.get("_beenden")))))
	var bis := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < bis and is_inside_tree() and get_tree() != null:
		andere = laufend.filter(func(w: Variant) -> bool: return is_instance_valid(w) and w != self)
		if andere.is_empty():
			return
		await get_tree().create_timer(0.1).timeout
	for w in andere:
		if is_instance_valid(w):
			if not demo:
				Kern.protokoll("Alter Kern nach 6 s noch da: hart beendet")
			w.call("_hart_weg")


## Sauber beenden (Browser zu): „ende“ an den Kern, bis 5 s auf sein Ende warten, sonst hart. Der Wirt hängt sich
## dafür an die Wurzel – die Ebene des Browsers darf schon weg sein; danach räumt er sich selbst weg.
func beenden(warum := "Browser zu") -> void:
	if _beenden:
		return
	_beenden = true
	_zaehler_schreiben(warum, true)
	_leitung_schreiben()
	var baum := get_tree()
	if baum and get_parent() != baum.root:
		_umzug = true
		reparent(baum.root)
		_umzug = false
	if _sim:
		senden("ende")
		_ende()
		queue_free()
		return
	if _io != null:
		var line := P.befehl("ende", {})
		_io.store_buffer(line.to_utf8_buffer())
		_io.flush()
	var pid := _pid
	var bis := Time.get_ticks_msec() + 5000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < bis and baum:
		await baum.create_timer(0.1).timeout
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
		if not demo:
			Kern.protokoll("Kern nach 5 s noch da: hart beendet")
	elif pid > 0 and not demo:
		Kern.protokoll("Kern beendet (%s) nach %.1f s, Rückgabe %s" % [warum, (Time.get_ticks_msec() - _start_ms) / 1000.0, ausgang_text(OS.get_process_exit_code(pid))])
	_ende()
	queue_free()


func _hart_weg() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_beenden = true
	_ende()
	queue_free()


func _echt_starten() -> void:
	if not Helper.available:
		_scheitern("start", "H0 Helfer läuft nicht")
		return
	if kern() == "webview2" and not spotify:
		_webview2_starten()
		return
	if not Kern.bereit():
		_scheitern("kern")
		return
	if not _auslegen_kern():
		_scheitern("pruefung", "H2 Kern-Dateien neben dem Helfer")
		return
	var st: String = await Kern.stummel_auffrischen()
	if st != "":
		_scheitern("pruefung", "H3 " + st)
		return
	var b: Dictionary = await Helper.run("kern-bauen", {}, 300.0)
	if not (b.ok and b.result is Dictionary and bool(b.result.get("ok", false))):
		_scheitern("start", "H1 kern-bauen: %s" % str(b.result.get("fehler", "?") if b.result is Dictionary else b.get("error", "keine Antwort")))
		return
	var exe := Kern.exe()
	if _RX_KERN_EXE.search(exe) == null or not FileAccess.file_exists(exe):
		Kern.vergessen("kern_pfad")
		_scheitern("kern_pfad", "P1 uzai-browser.exe fehlt")
		return
	var args := PackedStringArray(["--uzai-spotify" if spotify else "--uzai-kern", "--profil=" + _profil(), "--sprache=" + _sprache()])
	if grafik() == "software":
		args.append("--grafik=software")
	Kern.protokoll("Browser startet (Kern %s, Grafik %s, %s)" % [Kern.stand().fassung, grafik(), " ".join(args)])
	_prozess(exe, args)


## Grafik des Kerns: "hardware" (Standard) oder "software" (Rückfall, wenn der GPU-Prozess nicht läuft).
static func grafik() -> String:
	return "software" if str(Config.get_value("browser.kern_grafik", "hardware")) == "software" else "hardware"


func _webview2_starten() -> void:
	if not _auslegen():
		_scheitern("pruefung")
		return
	var r: Dictionary = await Helper.run("browser-bauen", {}, 120.0)
	var res: Dictionary = r.result if r.ok and r.result is Dictionary else {}
	var exe := str(res.get("exe", ""))
	if exe == "" or _RX_EXE.search(exe) == null or exe.contains(".."):
		_scheitern(str(res.get("fehler", "start")) if str(res.get("fehler", "")) in P.FEHLER else "start")
		return
	_prozess(exe, PackedStringArray(["--uzai-wirt", "--profil=" + _profil(), "--sprache=" + _sprache()]))


func _prozess(exe: String, args: PackedStringArray) -> void:
	var info: Dictionary = OS.execute_with_pipe(exe, args, false)
	if info.is_empty():
		_scheitern("start", "P2 Prozess startet nicht")
		return
	_io = info.get("stdio")
	_err = info.get("stderr")
	_pid = int(info.get("pid", 0))
	_seit = Time.get_ticks_msec()
	_start_ms = _seit
	if not self in laufend and not spotify:
		laufend.append(self)
	_seit_unix = int(Time.get_unix_time_from_system())
	_err_rest.clear()
	_buf.clear()                  # nichts vom vorigen Prozess (Neustart mit Software-Grafik) in die neue Leitung


static func _sprache() -> String:
	return "de-DE" if TranslationServer.get_locale().begins_with("de") else "en-US"


## Profil des Browsers: je Uzai-Profil ein eigenes, getrenntes Browser-Profil (Kennung nach festem Muster).
static func _profil() -> String:
	var id := str(Config.profile_id)
	return id if _RX_PROFIL.search(id) != null else "standard"


## WebView2-Dateien, Quelle des Wirts und Sprung-Skript neben den Helfer legen – nur geprüfte Dateien.
func _auslegen() -> bool:
	var dir := Config.path(ZIEL)
	DirAccess.make_dir_recursive_absolute(dir)
	for name in DATEIEN:
		var quelle := "res://assets/browser/webview2/" + str(name)
		if FileAccess.get_sha256(quelle) != DATEIEN[name]:
			return false
		var ziel := dir.path_join(name)
		if FileAccess.get_sha256(ziel) == DATEIEN[name]:
			continue
		if not _kopieren(quelle, ziel) or FileAccess.get_sha256(ziel) != DATEIEN[name]:
			return false
	for name in QUELLEN:
		if not _kopieren("res://helper/" + str(name), dir.path_join(str(name))):
			return false
	return true


## CEF-Kern: Quellen, Skripte, Filterliste und Start-Stummel neben den Helfer (browser_kern.gd dateien_auslegen).
func _auslegen_kern() -> bool:
	var fehlt := Kern.dateien_auslegen()
	if fehlt != "":
		Kern.protokoll("Start: " + fehlt + " fehlt")
	return fehlt == ""


static func _kopieren(von: String, nach: String) -> bool:
	var b := FileAccess.get_file_as_bytes(von)
	if b.is_empty():
		return false
	var f := FileAccess.open(nach, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(b)
	f.close()
	return true


func _scheitern(code: String, detail := "") -> void:
	fehler = code
	if detail == "" and _grund != "":
		detail = _grund
	diagnose = (code + " " + _kurz(detail)).strip_edges()
	if not demo:
		Kern.protokoll("Browser startet nicht: %s%s" % [code, (" – " + detail) if detail != "" else ""])
	_seit = 0
	_leitung_schreiben()
	_aus = true
	ereignis.emit({ "t": "fehler", "code": code if code in P.FEHLER else "start" })
	beendet.emit(code)


# --- Den CEF-Kern laden (erstes Öffnen) --------------------------------------------------------------

## Lädt den CEF-Kern über den gemeinsamen Lauf (browser_kern_lauf.gd; läuft er schon – etwa von der Startbühne –,
## wartet dies nur auf ihn). fortschritt(schritt, prozent). "" oder ein kurzer Grund. Ohne Windows nur gespielt.
func kern_laden(fortschritt: Callable) -> String:
	var l: Node = Lauf.starten(demo)
	if l == null:
		return "Start"
	l.connect("fortschritt", func(sch: String, pz: int, _a: float) -> void:
		if fortschritt.is_valid():
			fortschritt.call(sch, pz))
	var grund: String = await l.fertig
	return grund


# --- Leitung ---------------------------------------------------------------------------------------

## Befehl an den Kern. Passt er nicht ins Schema, geht er nie hinaus (false, gezählt).
func senden(art: String, daten: Dictionary = {}) -> bool:
	var line := P.befehl(art, daten)
	if line == "":
		verworfen += 1
		return false
	_leitung_merken("→", art)
	_zaehlen("→" + art)
	if _sim:
		var v: Variant = Fremd.json_roh(line)
		_sim.call("befehl", v)
		if art == "ende":
			_ende()
		return true
	if _io == null:
		return false
	_io.store_buffer(line.to_utf8_buffer())
	_io.flush()
	if art == "ende":
		_nachsehen()
	return true


## Der Kern geht nach „ende“ selbst; sonst nach 3 s hart (nur dieser eine Prozess).
func _nachsehen() -> void:
	var pid := _pid
	await get_tree().create_timer(3.0).timeout
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	_ende()


func _ende() -> void:
	laufend.erase(self)
	if _aus:
		return
	_leitung_schreiben()
	_aus = true
	bereit = false
	_sim = null
	_io = null
	_err = null
	_pid = 0
	beendet.emit("ende")


func _exit_tree() -> void:
	if _umzug:
		return
	laufend.erase(self)
	if laeuft():
		senden("ende")
		if _pid > 0 and OS.is_process_running(_pid):
			OS.kill(_pid)


func _process(dt: float) -> void:
	if _sim:
		_sim.call("schritt", dt)
		return
	if _io == null:
		return
	# Erst, was vom letzten Bild noch liegt; gelesen wird nur weiter, solange in diesem Bild Platz ist.
	var n := _zeilen_abarbeiten(0)
	while n < MAX_ZEILEN_JE_BILD and _io != null:
		var chunk := _io.get_buffer(65536)
		if chunk.is_empty():
			break
		_buf.append_array(chunk)
		n = _zeilen_abarbeiten(n)
		# Ein Kern, der ohne Zeilenende flutet: Leitung zu (die längste erlaubte Zeile ist eine Spotify-Antwort).
		if _buf.size() > P.MAX_ZEILE and _buf.find(10) < 0:
			_buf.clear()
			_scheitern("absturz")
			return
	if _io == null:
		return
	if _err:
		_err_merken(_err.get_buffer(65536))
	if Engine.get_process_frames() % 60 == 0 and _pid > 0 and not OS.is_process_running(_pid) and not _aus:
		_prozess_aus()
	elif bereit and not _beenden and Time.get_ticks_msec() - _zaehler_ms > 60000:
		_zaehler_ms = Time.get_ticks_msec()
		_zaehler_schreiben("Zwischenstand")
	elif _seit > 0 and not bereit and not _aus and Time.get_ticks_msec() - maxi(_seit, _letzte_zeile) > int(START_ZEIT_S * 1000.0):
		# Erst, wenn wirklich nichts mehr kommt: 60 s ohne eine Zeile vom Kern und ohne „bereit“.
		_protokoll_reste("kein „bereit“ und %d s keine Zeile vom Kern" % int(START_ZEIT_S))
		if _pid > 0 and OS.is_process_running(_pid):
			OS.kill(_pid)
		_scheitern("start", "Z1 kein Handshake nach %d s" % int(START_ZEIT_S))


## Ganze Zeilen aus dem Puffer an _zeile geben, höchstens bis MAX_ZEILEN_JE_BILD in diesem Bild (n: schon
## verarbeitet). Was darüber liegt, bleibt im Puffer und kommt im nächsten Bild; gelesen wird erst wieder, wenn
## Platz ist – flutet der Kern, staut es sich in seiner Leitung statt in Uzai. (Vorher galt die Grenze nur zwischen
## zwei Lesevorgängen: Ein Block mit zehntausenden kurzen Zeilen wurde in einem Bild abgearbeitet.)
func _zeilen_abarbeiten(n: int) -> int:
	var ab := 0
	while n < MAX_ZEILEN_JE_BILD:
		var nl := _buf.find(10, ab)
		if nl < 0:
			break
		var line := _buf.slice(ab, nl).get_string_from_utf8()
		ab = nl + 1
		n += 1
		_zeile(line)
	if ab > 0:
		_buf = _buf.slice(ab)
	return n


## Der Kern-Prozess ist weg: Rückgabewert, letzte Zeilen von stderr und – falls neu – debug.log des Bootstraps ins
## Protokoll; hat der Kern seinen Grund schon gemeldet, nur das (die Oberfläche hat ihn schon).
func _prozess_aus() -> void:
	var code := OS.get_process_exit_code(_pid)
	if _err:
		_err_merken(_err.get_buffer(65536))
	var ausgang := ausgang_text(code)
	laufend.erase(self)
	# Ende auf Wunsch (Browser zu): normal, beenden() räumt auf.
	if _beenden:
		return
	_protokoll_reste("Kern-Prozess endete nach %.1f s: %s" % [(Time.get_ticks_msec() - _start_ms) / 1000.0, ausgang])
	_zaehler_schreiben("Kern weg", true)
	# Chromium gibt auf, wenn der GPU-Prozess in keiner Stufe läuft (gpu_data_manager_impl_private.cc
	# FallBackToNextGpuMode): einmal je Sitzung mit Software-Grafik neu – gemerkt, in den Einstellungen zurückstellbar.
	if gpu_unbrauchbar(_err_rest.get_string_from_utf8()) and grafik() != "software" and not _software_versucht and not demo:
		_software_versucht = true
		Config.set_value("browser.kern_grafik", "software")
		Kern.protokoll("GPU-Prozess unbrauchbar: neuer Start mit Software-Grafik (Einstellung „Grafik“ im Menü Browser-Kern)")
		Toasts.show_toast("Browser nutzt Software-Grafik", "Der Grafikprozess lief nicht. Umstellen: Browser-Kern › Grafik.", "browser")
		_io = null
		_err = null
		_pid = 0
		_seit = 0
		_grund = ""
		_echt_starten()
		return
	if _gemeldet:
		_seit = 0
		_ende()
		return
	# Rückgabe 0 ohne Wunsch: der Kern hat sich selbst beendet (Fenster geschlossen, Leitung zu) – kein Absturz.
	if (code & 0xFFFFFFFF) == 0:
		Kern.protokoll("Kern hat sich selbst beendet (0) – Browser schließt")
		_seit = 0
		_aus = true
		beendet.emit("kern_ende")
		return
	_scheitern("absturz", _grund if _grund != "" else ausgang)


func _err_merken(b: PackedByteArray) -> void:
	if b.is_empty():
		return
	_err_rest.append_array(b)
	if _err_rest.size() > ERR_MAX:
		_err_rest = _err_rest.slice(_err_rest.size() - ERR_MAX)


## Eine Zeile mit dem Grund, dazu stderr (gekürzt) und debug.log des Bootstraps (nur wenn seit dem Start geschrieben).
func _protokoll_reste(was: String) -> void:
	if demo:
		return
	Kern.protokoll(was)
	var e := _err_rest.get_string_from_utf8().strip_edges()
	if e != "":
		Kern.protokoll("stderr: " + e.right(1500), 1600)
	var dl := Kern.wurzel().path_join("app/debug.log")
	if FileAccess.file_exists(dl) and FileAccess.get_modified_time(dl) + 2 >= _seit_unix:
		var f := FileAccess.open(dl, FileAccess.READ)
		if f:
			var n := f.get_length()
			f.seek(maxi(0, n - 1500))
			var t := f.get_buffer(1500).get_string_from_utf8().strip_edges()
			f.close()
			if t != "":
				Kern.protokoll("debug.log: " + t, 1600)


## Die ersten Befehle und Ereignisse nach dem Start (nur die Art, keine Inhalte, keine Adressen) ins Protokoll:
## einmal gesammelt, sobald LEITUNG_MAX erreicht sind (oder beim Ende des Lebens des Wirts).
func _leitung_merken(richtung: String, art: String) -> void:
	if demo or _leitung.size() >= LEITUNG_MAX:
		return
	_leitung.append(richtung + art)
	if _leitung.size() == LEITUNG_MAX:
		_leitung_schreiben()


func _zaehlen(art: String) -> void:
	_zaehler[art] = int(_zaehler.get(art, 0)) + 1


## Alle Befehle (→) und Ereignisse (←) der Sitzung, gezählt je Art (ohne Inhalt): beim Ende und höchstens
## minütlich, wenn sich etwas geändert hat – so zeigt das Protokoll, ob Steuerbefehle den Kern erreichen.
func _zaehler_schreiben(was: String, immer := false) -> void:
	if demo or _zaehler.is_empty():
		return
	var arten := _zaehler.keys()
	arten.sort_custom(func(a: String, b: String) -> bool: return int(_zaehler[a]) > int(_zaehler[b]))
	var teile: Array = []
	for a in arten.slice(0, 28):
		teile.append("%s %d" % [a, int(_zaehler[a])])
	var t := " ".join(PackedStringArray(teile))
	if t == _zaehler_stand and not immer:
		return
	_zaehler_stand = t
	_zaehler_ms = Time.get_ticks_msec()
	Kern.protokoll("Leitung gesamt (%s): %s" % [was, t], 900)


func _leitung_schreiben() -> void:
	if demo or _leitung.is_empty() or _leitung_geschrieben:
		return
	_leitung_geschrieben = true
	Kern.protokoll("Leitung (erste %d): %s" % [_leitung.size(), " ".join(PackedStringArray(_leitung))])


## Eine Zeile vom Kern, die nicht ins Schema passt: je Art einmal ins Protokoll (nur die Art).
func _verworfen_melden(line: String) -> void:
	if demo:
		return
	var v: Variant = Fremd.json_roh(line.left(P.MAX_EREIGNIS)) if line.length() <= P.MAX_EREIGNIS else null
	var art := str((v as Dictionary).get("t", "?")) if v is Dictionary else "kein JSON"
	art = Kern.anonym(art, 24)
	if art in _verworfene or _verworfene.size() >= 20:
		return
	_verworfene.append(art)
	Kern.protokoll("Leitung: Ereignis vom Kern verworfen (Schema): %s" % art)


## Hat Chromium wegen des GPU-Prozesses aufgegeben? (stderr des Kerns)
static func gpu_unbrauchbar(err: String) -> bool:
	return err.contains("GPU process isn't usable")


## Rückgabewert des Kern-Prozesses → „0x80000003 Abbruch im Bootstrap/CEF …“ (bekannte Werte benannt).
static func ausgang_text(code: int) -> String:
	if code == -1:
		return "Rückgabewert unbekannt"
	var c := code & 0xFFFFFFFF
	var t := ("0x%08X" % c) if c >= 0x10000 else str(c)
	if AUSGANG.has(c):
		return t + " " + str(AUSGANG[c])
	if c >= 100 and c < 200:
		return t + " Installer-Code"
	return t


## Kurz für den Hinweis: der Code vorn („K14“, „0x80000003“, „H1“).
static func _kurz(detail: String) -> String:
	var k := detail.find(" ")
	return (detail if k < 0 else detail.substr(0, k)).left(16)


## Eine Zeile vom Kern: erst durch das Schema, dann weiter. Dazu die Pflege des CEF-Kerns: nach dem Start die
## Sperrliste des Blockers, höchstens einmal am Tag die Update-Prüfung, nach der ersten geladenen Seite „gesund“
## (Rückfall-Schutz des Installers: eine Fassung, die nie eine Seite zeigte, fällt beim nächsten Start zurück).
## „gesund“ gilt je Start und auch für die Spotify-Sitzung: Der Installer zählt jeden unbestätigten Start als
## Fehlschlag und tauscht die Fassung auch selbst (Update) – ein einmal gemerktes „gesund“ deckte die neue nicht.
func _zeile(line: String) -> void:
	_letzte_zeile = Time.get_ticks_msec()
	var e := P.ereignis(line.strip_edges())
	if e.is_empty():
		_verworfen_melden(line)
		return
	_leitung_merken("←", str(e.t))
	_zaehlen("←" + str(e.t))
	if e.t == "bereit":
		bereit = true
		if not demo:
			Kern.protokoll("Browser bereit nach %.1f s (Kern %s)" % [(Time.get_ticks_msec() - _seit) / 1000.0 if _seit > 0 else 0.0, str(e.version).left(96)])
		_seit = 0
		kern_fassung = str(e.version)
		_nach_start()
	elif e.t == "kern" and str(e.stand) == "info" and not demo:
		Kern.protokoll("Kern: %s" % str(e.text), 600)
	elif e.t == "kern" and str(e.stand) == "fehler" and not demo:
		if str(e.schritt) == "grund":
			_grund = str(e.text)
		Kern.protokoll("Kern meldet: %s" % str(e.text), 600)
	elif e.t == "fehler":
		_gemeldet = true
		diagnose = (str(e.code) + " " + _kurz(_grund)).strip_edges()
		if not demo:
			Kern.protokoll("Kern-Fehler: %s%s" % [e.code, (" – " + _grund) if _grund != "" else ""])
	elif e.t == "tab" and not demo and (spotify or kern() == "cef") and not bool(e.laedt) and str(e.url) != "about:blank" and str(e.url) != "":
		_gesund()
	elif e.t == "kern" and str(e.stand) == "update" and str(e.fassung) != "":
		Config.set_value("browser.kern_naechste", str(e.fassung))
	ereignis.emit(e)


func _nach_start() -> void:
	if spotify:
		return
	var aus: Variant = Config.get_value("browser.blocker_aus", [])
	if aus is Array and not (aus as Array).is_empty():
		senden("blocker-liste", { "hosts": (aus as Array).slice(0, 400) })
	if demo or kern() != "cef":
		return
	var st := Kern.stand()
	if Kern.pruefung_faellig(int(st.pruefung), int(Time.get_unix_time_from_system())):
		Config.set_value("browser.kern_pruefung", int(Time.get_unix_time_from_system()))
		senden("kern", { "aktion": "update" })


func _gesund() -> void:
	if _gesund_gemeldet:
		return
	_gesund_gemeldet = true
	if senden("kern", { "aktion": "gesund" }):
		Config.set_value("browser.kern_gesund", true)


## Vorführmodus: die Platzhalter-Seite eines Tabs zum Zeichnen (nur Demo, sonst {}).
func demo_seite(tab: int) -> Dictionary:
	return _sim.call("seite", tab) if _sim else {}

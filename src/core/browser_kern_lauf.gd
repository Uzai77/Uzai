extends Node
## Der Browser-Kern wird eingerichtet – im Hintergrund, unabhängig von der Oberfläche (docs/BROWSER_PLAN.md 2.2).
## Beim ersten Öffnen des Bereichs Browser (Startbühne, browser_view.gd) startet Uzai das Laden selbst, ohne
## eigenen Druck; mit browser.kern_vorab (Einrichtung › Extras) schon kurz nach dem Start von Uzai. Die Startbühne
## und der Dialog (browser_kern_ui.gd) zeigen denselben Lauf; X auf der Bühne bzw. „Abbrechen“ hält ihn an.
## Geprüft wird wie bisher in browser_kern.gd laden(): nur der offizielle Host, SHA-1 und SHA-256, eigener
## Entpacker im Helfer, Katalog und Zertifikat im offiziellen Installer, später Start nur mit Sandbox.
##
## Ein Lauf zur Zeit (Lauf.jetzt). stand(): { laeuft, schritt, prozent, anteil, fehler, fertig }. Ohne Windows
## (Vorführung, Proben) wird der Ablauf nur gespielt.

signal fortschritt(schritt: String, prozent: int, anteil: float)
signal fertig(grund: String)

const Kern := preload("res://src/core/browser_kern.gd")
const P := preload("res://src/core/browser_protokoll.gd")
const Zustand := preload("res://src/core/zustand.gd")

const ABGEBROCHEN := "Abgebrochen – nichts installiert."
const INSTALL_MAX_S := 1800.0
const VORAB_NACH_S := 90.0       ## browser.kern_vorab: so lange nach dem Start von Uzai warten (Start nicht stören)
## Ein Balken über alles: Liste 0–4, Download 4–70, Prüfen 70–74, Auslegen 74–82, Installer 82–100.
const VON := { "liste": 0.0, "download": 0.04, "pruefen": 0.7, "auslegen": 0.74, "install": 0.82 }
const BIS := { "liste": 0.04, "download": 0.7, "pruefen": 0.74, "auslegen": 0.82, "install": 1.0 }
## Schritte des offiziellen Installers (WM_COPYDATA step_name) → Text; alles gehört zum Schritt „install“.
const INSTALLER := {
	"downloading": "Installer lädt", "verifying": "Installer prüft Signatur", "extracting": "Installer entpackt",
	"installing": "Installer richtet ein", "finalizing": "Installer schließt ab",
}

static var jetzt: Node               ## der laufende (oder zuletzt gelaufene) Lauf
static var abgebrochen := false      ## in dieser Sitzung abgebrochen: nicht von selbst neu starten
static var auto_versucht := false    ## in dieser Sitzung schon von selbst gestartet

## Schritte eines Laufs in fester Folge; das Ergebnis (fertig, Fehler, Abbruch) meldet _ablauf am Ende,
## das Feld behält den letzten Schritt (die Oberfläche zeigt ihn mit dem Grund).
const ZUSTAENDE_SCHRITT := { "*": ["fertig", "fehler", "abgebrochen"], "": ["liste"], "liste": ["download"], "download": ["pruefen"],
	"pruefen": ["auslegen"], "auslegen": ["install"], "install": [], "fertig": [], "fehler": [], "abgebrochen": [] }
var schritt := "":
	set(neu):
		Zustand.wechsel("browser.kern_einrichten", ZUSTAENDE_SCHRITT, schritt, neu)
		schritt = neu
var schritt_text := ""
var prozent := 0
var anteil := 0.0
var laeuft := false
var grund := ""                      ## Ergebnis: "" = fertig, sonst der Grund für den Nutzer
var ende := false
var stop := { "stop": false }


## Muss der Kern noch eingerichtet werden? Nur echt unter Windows mit CEF als Kern.
static func noetig() -> bool:
	var demo := "--demo" in OS.get_cmdline_user_args() or not Config.is_windows()
	var k := str(Config.get_value("browser.kern", "cef"))
	return not demo and k == "cef" and not Kern.bereit()


static func aktiv() -> bool:
	return is_instance_valid(jetzt) and bool(jetzt.laeuft)


## Was die Oberfläche zeigt (auch ohne Lauf).
static func stand() -> Dictionary:
	if not is_instance_valid(jetzt):
		return { "laeuft": false, "schritt": "", "text": "", "prozent": 0, "anteil": 0.0, "fehler": "", "fertig": false }
	return { "laeuft": jetzt.laeuft, "schritt": jetzt.schritt, "text": jetzt.schritt_text, "prozent": jetzt.prozent, "anteil": jetzt.anteil,
		"fehler": jetzt.grund if jetzt.ende else "", "fertig": jetzt.ende and jetzt.grund == "" }


## Startet einen Lauf (oder gibt den laufenden zurück). gespielt: ohne Netz und Dateien (Vorführung, Proben).
static func starten(gespielt := false) -> Node:
	if aktiv():
		return jetzt
	var baum := Engine.get_main_loop() as SceneTree
	if baum == null:
		return null
	if is_instance_valid(jetzt):
		jetzt.queue_free()
	abgebrochen = false
	var l = load("res://src/core/browser_kern_lauf.gd").new()
	l.name = "BrowserKernLauf"
	l.laeuft = true                   # gleich als laufend: ein zweites starten() im selben Bild nimmt diesen Lauf
	jetzt = l
	baum.root.add_child(l)
	l.call_deferred("_ablauf", gespielt or not noetig())
	return l


## Von selbst (erstes Öffnen des Bereichs): nur, wenn nötig, einmal je Sitzung und nicht nach einem Abbruch.
static func automatisch() -> void:
	if auto_versucht or abgebrochen or aktiv() or not noetig():
		return
	auto_versucht = true
	Kern.protokoll("Einrichten startet von selbst (Bereich Browser)")
	starten()


## Vorab (browser.kern_vorab, Einrichtung › Extras): kurz nach dem Start von Uzai, wenn der Nutzer zugestimmt hat.
static func vorab(baum: SceneTree) -> void:
	if not bool(Config.get_value("browser.kern_vorab", false)) or not noetig():
		return
	await baum.create_timer(VORAB_NACH_S).timeout
	if Launcher.in_game:
		return
	if not auto_versucht and not abgebrochen and not aktiv() and noetig():
		auto_versucht = true
		Kern.protokoll("Einrichten startet vorab (Einstellung browser.kern_vorab)")
		starten()


func abbrechen() -> void:
	if not laeuft:
		return
	stop.stop = true
	abgebrochen = true
	Kern.protokoll("Abbruch gewünscht")


func _ablauf(gespielt: bool) -> void:
	laeuft = true
	ende = false
	grund = ""
	_melden("liste", 0)
	if gespielt:
		for s in [["liste", 40], ["download", 6], ["download", 22], ["download", 41], ["download", 63], ["download", 88], ["pruefen", 100], ["auslegen", 50],
				["install", 20], ["install", 55], ["install", 90], ["install", 100]]:
			await get_tree().create_timer(0.35).timeout
			if bool(stop.stop):
				grund = ABGEBROCHEN
				break
			_melden(str(s[0]), int(s[1]))
	else:
		grund = await Kern.laden(Callable(self, "_melden"), Callable(self, "_install_lauf"), stop)
		if grund != "" and bool(stop.stop):
			grund = ABGEBROCHEN
	laeuft = false
	ende = true
	Kern.protokoll("Ergebnis: " + ("fertig" if grund == "" else grund))
	Zustand.wechsel("browser.kern_einrichten", ZUSTAENDE_SCHRITT, schritt, "fertig" if grund == "" else ("abgebrochen" if grund == ABGEBROCHEN else "fehler"))
	fertig.emit(grund)


## Fortschritt eines Schritts (liste, download, pruefen, auslegen, install) in Prozent.
func _melden(sch: String, pz: int, text := "") -> void:
	schritt = sch
	prozent = clampi(pz, 0, 100)
	schritt_text = text
	anteil = lerpf(float(VON.get(sch, 0.0)), float(BIS.get(sch, 1.0)), prozent / 100.0)
	fortschritt.emit(schritt, prozent, anteil)


## uzai-kernladen.exe --uzai-install: eine Konfigurationszeile hinein, kern-Ereignisse heraus, bis fertig oder
## fehler (oder der Prozess endet, oder Abbruch). { stand, text }.
func _install_lauf(lader: String, zeile: String) -> Dictionary:
	if zeile == "" or RegEx.create_from_string(Kern.EXE_MUSTER).search(lader) == null or not FileAccess.file_exists(lader):
		return { "stand": "fehler", "text": "Lader fehlt" }
	var info: Dictionary = OS.execute_with_pipe(lader, PackedStringArray(["--uzai-install"]), false)
	if info.is_empty():
		return { "stand": "fehler", "text": "Lader startet nicht" }
	var io: FileAccess = info.get("stdio")
	var err: FileAccess = info.get("stderr")
	var pid := int(info.get("pid", 0))
	io.store_buffer(zeile.to_utf8_buffer())
	io.flush()
	var buf := PackedByteArray()
	var bis := Time.get_ticks_msec() + int(INSTALL_MAX_S * 1000.0)
	var letzte := {}
	var nachlauf := 0
	var ergebnis := {}
	while Time.get_ticks_msec() < bis and is_inside_tree() and ergebnis.is_empty():
		await get_tree().process_frame
		if bool(stop.stop):
			ergebnis = { "stand": "fehler", "text": ABGEBROCHEN }
			break
		if err:
			err.get_buffer(65536)      # mitlesen, sonst blockiert ein voller Fehlerkanal
		var chunk := io.get_buffer(65536)
		if not chunk.is_empty():
			buf.append_array(chunk)
			if buf.size() > P.MAX_EREIGNIS:
				ergebnis = { "stand": "fehler", "text": "Installer schreibt zu viel" }
				break
		while ergebnis.is_empty():
			var nl := buf.find(10)
			if nl < 0:
				break
			var e := P.ereignis(buf.slice(0, nl).get_string_from_utf8().strip_edges())
			buf = buf.slice(nl + 1)
			if e.is_empty():
				continue
			if str(e.t) == "fehler":
				ergebnis = { "stand": "fehler", "text": "Installer: " + str(e.get("code", "")) }
			elif str(e.t) == "kern":
				letzte = e
				if str(e.stand) in ["fertig", "fehler"]:
					ergebnis = { "stand": str(e.stand), "text": str(e.get("text", "")) }
				else:
					var sch := str(e.get("schritt", ""))
					_melden("install", int(e.get("prozent", 0)), str(INSTALLER.get(sch, "")))
		# Prozess zu Ende: noch zwei Bilder lesen, was er zuletzt schrieb.
		if ergebnis.is_empty() and pid > 0 and not OS.is_process_running(pid):
			nachlauf += 1
			if nachlauf > 2:
				break
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	if ergebnis.is_empty():
		ergebnis = { "stand": "fehler", "text": str(letzte.get("text", "Der Installer endete ohne Ergebnis.")) }
	return ergebnis

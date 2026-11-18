extends Node
## Uzai aktualisiert sich selbst über die Releases auf GitHub (docs/SECURITY.md „Updates“).
##
## Ablauf: Höchstens einmal am Tag (oder auf Wunsch sofort) fragt Uzai GitHub nach dem neuesten Release. Ist es
## neuer, lädt Uzai zuerst die Signatur (Uzai-<Fassung>-windows.zip.sig, kleines JSON) und prüft sie mit dem
## öffentlichen Schlüssel, der in Uzai steckt (SCHLUESSEL): RSA mit SHA-256 über nachricht() – Fassung, Dateiname und
## Prüfsumme des Pakets. Nur mit gültiger Signatur lädt Uzai das Paket, über Net.download_verified (also nur mit genau
## dieser Prüfsumme), und entpackt daraus nur die Dateien aus ERLAUBT in einen eigenen Ordner (jede Datei nach dem
## Schreiben gegen die Bytes aus dem Paket geprüft, Größe und Prüfsumme gemerkt). Eingespielt wird beim Beenden: Der
## Helfer (-Update) wartet, bis Uzai weg ist, prüft die Prüfsummen, kopiert die neuen Dateien als .neu neben die alten
## und tauscht dann jede in einem Schritt (ReplaceFile, die alte bleibt als .alt); bei einem Fehler kommen alle alten
## zurück. Wird er mittendrin beendet, ist jede Datei ganz alt oder ganz neu, nie halb oder weg.
##
## Wer das GitHub-Konto oder den Download-Server übernimmt, kann so kein fremdes Programm einspielen: Ohne den privaten
## Schlüssel (nur beim Herausgeber, nie im Repository; tools/release_signieren.gd) passt keine Signatur. Ist SCHLUESSEL
## leer, meldet Uzai ein Update nur und spielt nie etwas ein.

signal geaendert

const Logdatei := preload("res://src/core/logdatei.gd")
const Fremd := preload("res://src/core/fremd.gd")
const Arbeit := preload("res://src/core/arbeit.gd")
const UP := preload("res://src/core/update_pruefung.gd")

## Woher die Releases kommen (eine Stelle für alles: Config.REPO).
const REPO := preload("res://src/core/config.gd").REPO
## Öffentlicher Schlüssel (PEM, RSA-4096) zur Prüfung der Signaturen. Leer: Updates nur melden, nie einspielen.
## Angelegt am 17.11.2026 mit tools/release_signieren.gd --neu; der private Teil liegt nur beim Herausgeber.
const SCHLUESSEL := """-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEArmXKSGtptxh8HdnMHLvo
oSOK+IJDdOHmQ2il6wcmkrozhkhM3kSdGfFRx5NIvXnR9AddjMLVruXv+wfJIfoP
Dn3lDKvlsjNjYENAk0stMyMJDZNcCEnThQo33tog2ksYbXKUpH6U5LTYxP+hHuHq
JEnisbYsJrCr6x9AL6a948y/ZcN2JdGQllymlLG/ZCr8PdySCbLekmsBujhqkysm
gPtoUwsFkz1+6P5tFyTWDdEN/LPlzhu0IKqttp+xujZf9Oy9YuYR4AQMij/9r4+n
/KC+S4wFJ3v+MORzJtgKHOq5rPuwKp+6dPuNKyzumjTzawwy1CYSe23SzBB5Izb0
TcWN+Ax8nNFR54QHmqJItiUvxxYtYAM0K006msknfA6tViCsSdRRK+BWbIjtXW1b
wQOyIln4mvDYN5ZgvK741l9hYMYHFG8Y2uAfH69yTR50e3kDY9w/Ped8UfVNM/Us
uBtcgJThKAWKP18PBDwX3hbYqhzOKp+C92374izUnO4+f+jxExn6BJQEloC+4NLB
HiJHLKw+3HayvxVfSoxR5Zgp5gSQxXQYwlpuJGcy+TsRc3+p0Honp0TmWWpAn+mz
G6IMP2t+MSINiYEN6HucnmRUCba6PEsKi/TsI2dxnopzP3ky4sijjqDm/mBcOxqt
JRhd7dBPNwRfxBWXsb37OKMCAwEAAQ==
-----END PUBLIC KEY-----
"""
const ABSTAND := 24 * 3600                ## so oft fragt Uzai von selbst
const NACH_FEHLER := 3 * 3600             ## nach einem Fehlschlag (kein Netz, Download abgebrochen) so viel früher
const ERSTE_PRUEFUNG_S := 90.0            ## nach dem Start erst so spät: der Start bleibt frei
const MAX_PAKET := 400 * 1024 * 1024
const MAX_SIGNATUR := 16 * 1024
const MAX_ANTWORT := 2 * 1024 * 1024
const LOG := "logs/update.log"
const ZUSTAND := "update/zustand.json"
const ERGEBNIS := "update/ergebnis.json"

var zustand := {}          ## { geprueft, versucht, neueste, seite, bereit: { fassung, ordner, dateien, groessen, sha256 }, fehler }
var laeuft := false        ## sucht oder lädt gerade
var neu_starten := false   ## „Jetzt einspielen“: nach dem Einspielen Uzai wieder starten
var _eingereicht := false


func _ready() -> void:
	var z: Variant = Config.read_json(Config.path(ZUSTAND), {})
	zustand = z if z is Dictionary else {}
	_ergebnis_melden()
	# Schon eingespielt, aber das Ergebnis kam nie an (Helfer mittendrin beendet): Eintrag und Ordner weg.
	var b: Variant = zustand.get("bereit")
	if b is Dictionary and not UP.neuer(str(b.get("fassung", "")), Config.VERSION):
		zustand.erase("bereit")
		_alte_ordner_weg(Config.path("update"), "")
		_speichern()


## Darf dieses Uzai sich selbst aktualisieren? Nur das fertige Programm unter Windows, nicht im Editor, in Proben
## oder im Vorführmodus.
func aktiv() -> bool:
	if not Config.is_windows() or not OS.has_feature("template") or modus() == "aus":
		return false
	for a in OS.get_cmdline_user_args():
		if a == "--demo" or a == "--no-boot" or a.begins_with("--uzai-"):
			return false
	return true


static func modus() -> String:
	var m := str(Config.get_value("system.updates", "auto"))
	return m if m in ["auto", "melden", "aus"] else "auto"


## Nach dem Start und danach stündlich nachsehen, ob der letzte gelungene Blick lange genug her ist. Ein Fehlschlag
## (kein Netz nach dem Aufwachen) zählt nicht als geprüft: dann nach NACH_FEHLER noch einmal. So prüft auch ein Uzai,
## das tagelang im Standby läuft.
func spaeter_pruefen() -> void:
	if not aktiv():
		return
	await get_tree().create_timer(ERSTE_PRUEFUNG_S).timeout
	while is_inside_tree():
		var faellig := Time.get_unix_time_from_system() - float(zustand.get("geprueft", 0)) >= ABSTAND
		# Nur wenn GitHub nicht erreichbar war: Scheiterte das Laden selbst (Prüfsumme, kaputtes Release), nicht alle 3 h
		# bis zu 400 MB erneut, sondern erst am nächsten Tag.
		var nach_fehler := bool(zustand.get("pruef_fehler", false)) and Time.get_unix_time_from_system() - float(zustand.get("versucht", 0)) >= NACH_FEHLER
		if faellig or nach_fehler:
			await pruefen()
		await get_tree().create_timer(3600.0).timeout


## Nach dem neuesten Release fragen; ist es neuer und Updates stehen auf „Automatisch“, gleich laden.
func pruefen(sofort := false) -> void:
	if laeuft or not aktiv():
		return
	laeuft = true
	geaendert.emit()
	var r: Dictionary = await Net.request("https://api.github.com/repos/%s/releases/latest" % REPO,
		PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: Uzai"]), HTTPClient.METHOD_GET, "", 20.0, "api", MAX_ANTWORT)
	zustand["versucht"] = int(Time.get_unix_time_from_system())
	var rel: Variant = Fremd.json((r.body as PackedByteArray).get_string_from_utf8()) if bool(r.get("ok", false)) else null
	if not (rel is Dictionary):
		zustand["pruef_fehler"] = true
		_fehler("Keine Antwort von GitHub (HTTP %d)" % int(r.get("code", 0)))
		return
	zustand["pruef_fehler"] = false
	var f := UP.fassung_aus_tag(str((rel as Dictionary).get("tag_name", "")))
	if f == "":
		_fehler("Release ohne gültige Fassung")
		return
	zustand["geprueft"] = int(Time.get_unix_time_from_system())
	zustand["neueste"] = f
	zustand["seite"] = str(rel.get("html_url", "")) if str(rel.get("html_url", "")).begins_with("https://github.com/") else ""
	zustand["fehler"] = ""
	_log("Geprüft: neueste %s, diese %s" % [f, Config.VERSION])
	_speichern()
	laeuft = false
	geaendert.emit()
	if not UP.neuer(f, Config.VERSION):
		return
	if bereit_fassung() == f:
		return
	if SCHLUESSEL == "" or (modus() == "melden" and not sofort) or not UP.ordner_beschreibbar(OS.get_executable_path().get_base_dir()):
		Toasts.show_toast("Update verfügbar", "Uzai %s ist da." % f, "refresh", { "ms": 6000 })
		return
	await laden(rel as Dictionary, f)


## Signatur prüfen, Paket mit genau dieser Prüfsumme laden, die erlaubten Dateien in einen eigenen Ordner.
func laden(rel: Dictionary, f: String) -> void:
	if laeuft:
		return
	laeuft = true
	geaendert.emit()
	var datei := UP.paket_name(f)
	var paket := UP.asset_finden(rel, datei, REPO)
	var sig := UP.asset_finden(rel, datei + ".sig", REPO)
	if paket.is_empty() or sig.is_empty() or int(paket.get("size", 0)) > MAX_PAKET:
		_fehler("Release ohne Paket oder Signatur")
		return
	var sr: Dictionary = await Net.request(str(sig.browser_download_url), PackedStringArray(["User-Agent: Uzai"]), HTTPClient.METHOD_GET, "", 20.0,
		"api", MAX_SIGNATUR)
	var geprueft := UP.signatur_pruefen(Fremd.json((sr.body as PackedByteArray).get_string_from_utf8()) if bool(sr.get("ok", false)) else null,
		f, datei, SCHLUESSEL)
	if not bool(geprueft.ok):
		_fehler("Signatur ungültig: " + str(geprueft.grund))
		return
	var wurzel := Config.path("update")
	DirAccess.make_dir_recursive_absolute(wurzel)
	var zip := wurzel.path_join(datei)
	var grund: String = await Net.download_verified(str(paket.browser_download_url), zip, str(geprueft.sha256))
	if grund != "":
		_fehler(grund)
		return
	var ordner := wurzel.path_join(f)
	# Ein alter Eintrag für denselben Ordner darf beim Entpacken nicht mehr gelten (sonst würde ein halb neu
	# entpackter Ordner eingespielt, wenn Uzai mittendrin schließt). Ein bereites älteres Update in einem anderen Ordner
	# bleibt, bis das neue ganz da ist.
	var b0: Variant = zustand.get("bereit")
	if b0 is Dictionary and str(b0.get("ordner", "")) == ordner:
		zustand.erase("bereit")
		_speichern()
	var v: Variant = await Arbeit.ergebnis(UP.entpacken.bind(zip, ordner), Arbeit.LANG)
	DirAccess.remove_absolute(zip)
	var e: Dictionary = v if v is Dictionary else {}
	if not bool(e.get("ok", false)):
		_fehler("Paket: " + str(e.get("grund", "unbekannt")))
		return
	zustand["bereit"] = { "fassung": f, "ordner": ordner, "dateien": e.dateien, "groessen": e.groessen, "sha256": e.sha256 }
	zustand["fehler"] = ""
	_speichern()
	_log("Bereit: %s (%s)" % [f, ", ".join(PackedStringArray(e.dateien))])
	_alte_ordner_weg(wurzel, f)
	laeuft = false
	geaendert.emit()
	Toasts.show_toast("Update bereit", "Uzai %s kommt beim Schließen." % f, "refresh", { "ms": 6000 })


func bereit_fassung() -> String:
	var b: Variant = zustand.get("bereit")
	if not (b is Dictionary) or not UP.neuer(str(b.get("fassung", "")), Config.VERSION) or not UP.bereit_ok(b):
		return ""
	return str(b.fassung)


## Beim Beenden: Liegt ein geprüftes Update bereit, übergibt Uzai es dem Helfer (-Update). Der wartet, bis Uzai weg
## ist, und spielt es dann ein. true, wenn er gestartet ist.
func einreichen() -> bool:
	if _eingereicht or not is_instance_valid(Config) or not is_instance_valid(Helper):
		return false
	if bereit_fassung() == "" or not aktiv() or Helper._script == "":
		return false
	var b: Dictionary = zustand.bereit
	var job := UP.auftrag(OS.get_process_id(), OS.get_executable_path(), str(b.ordner), b.dateien, str(b.fassung), neu_starten,
		Config.path(ERGEBNIS), b.sha256)
	var payload := Marshalls.utf8_to_base64(JSON.stringify(job))
	_eingereicht = OS.create_process(Helper.ps_exe(), Helper._ps_args(PackedStringArray(["-Update", payload])), false) > 0
	_log("Eingereicht: %s, neu starten %s → %s" % [str(b.fassung), str(neu_starten), "ok" if _eingereicht else "Helfer startet nicht"])
	return _eingereicht


## „Jetzt einspielen“: Uzai schließt sich, der Helfer spielt ein und startet Uzai wieder.
func jetzt_einspielen(main: Node) -> void:
	if bereit_fassung() == "":
		return
	neu_starten = true
	if main.has_method("_quit_uzai"):
		main.call("_quit_uzai", false)


func _exit_tree() -> void:
	# Jeder normale Weg hinaus (Alt+F4, Ausschalten, Neustart): ein bereites Update einspielen. Läuft Uzai danach
	# gleich wieder (Neustart), lässt der Helfer es liegen – dann beim nächsten Schließen.
	einreichen()


func _ergebnis_melden() -> void:
	var p := Config.path(ERGEBNIS)
	if not FileAccess.file_exists(p):
		return
	var e: Variant = Config.read_json(p, {})
	DirAccess.remove_absolute(p)
	if not (e is Dictionary):
		return
	if bool(e.get("ok", false)) and str(e.get("fassung", "")) == Config.VERSION:
		_log("Eingespielt: %s" % Config.VERSION)
		zustand.erase("bereit")
		_speichern()
		Toasts.show_toast("Aktualisiert", "Uzai %s" % Config.VERSION, "refresh", { "ms": 5000 })
	elif bool(e.get("verschoben", false)):
		# Neustart oder Profilwechsel: Uzai lief gleich wieder, das Update kommt beim nächsten Schließen – kein Fehler.
		_log("Verschoben: " + str(e.get("grund", "")).left(160))
	elif not bool(e.get("ok", false)):
		var grund := str(e.get("grund", "")).left(160)
		_log("Einspielen ging nicht: " + grund)
		Toasts.show_toast("Update ging nicht", "Uzai versucht es beim nächsten Schließen noch einmal.", "warning", { "ms": 6000 })


## Übersprungene Fassungen (je einige hundert MB) nicht liegen lassen: nur Ordner mit Fassungsnamen, nur flache Dateien.
static func _alte_ordner_weg(wurzel: String, behalten: String) -> void:
	for d in DirAccess.get_directories_at(wurzel):
		if d == behalten or UP.fassung_aus_tag(d) != d:
			continue
		var o := wurzel.path_join(d)
		for datei in DirAccess.get_files_at(o):
			DirAccess.remove_absolute(o.path_join(datei))
		DirAccess.remove_absolute(o)


func _fehler(t: String) -> void:
	zustand["fehler"] = t.left(200)
	_log(t)
	_speichern()
	laeuft = false
	geaendert.emit()


func _speichern() -> void:
	DirAccess.make_dir_recursive_absolute(Config.path("update"))
	Config.write_json(Config.path(ZUSTAND), zustand)


func _log(t: String) -> void:
	Logdatei.zeile(Config.path(LOG), t, 100000)

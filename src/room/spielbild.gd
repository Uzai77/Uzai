extends Node
## Das laufende Spiel im Fernseher des Zimmers (Punkt 131, Stufe 2). Läuft ein Spiel und du stehst im
## Zimmer (aufgestanden oder Guide › Dein Zimmer), zeigt der Fernseher es live weiter.
##
## Weg 1, „wgc“ (Windows Graphics Capture, Helfer „tv-fang“): Windows liefert die Bilder des
## Spielfensters selbst, die Grafikkarte rechnet sie klein (höchstens FANG, z. B. 960 × 540), der Helfer
## legt sie mit festem Kopf in eine Zwischendatei im Temp-Ordner (temporär markiert, bleibt im
## Arbeitsspeicher, wird beim Stoppen gelöscht). Uzai liest nur diese Datei, prüft Kennung, Größen und
## die Folgenummer vor und nach dem Bild und legt die Pixel in dasselbe Bild (gleiche Größe: keine neue
## Textur je Bild). Kein JPEG, kein Base64, und das Spiel wird nicht gebremst.
## Weg 2, „printwindow“ (Rückfall, nur wenn Weg 1 nicht geht – älteres Windows, Spiel mit
## Adminrechten): Befehl „window-frame“, ein kleines JPEG als Base64, nur im Speicher. PrintWindow
## zwingt Windows, das Spiel für jedes Bild anzuhalten – daher deutlich langsamer (TAKT).
## Uzai behält nur das letzte Bild (für den nahtlosen Übergang ins Spiel) und vergisst es mit dem
## Zimmer. Gespeichert wird es nie – außer du machst ausdrücklich einen Schnappschuss.
##
## Sparsam: nur solange das Zimmer vorn liegt und der Fernseher im Bild ist (sichtbar) – nie, solange
## das Spiel vorn liegt und das Zimmer dahinter wartet. Fast schwarze Bilder (exklusives Vollbild,
## minimiert) zählen als „kein Bild“ – dann zeigt der Fernseher Titel und „Läuft gerade“.
##
## Schwarz oder „Fenster 80070057“ bei Weg 1: Der Helfer stellt sich selbst darauf ein (Grafikkarte des
## Bildschirms, HDR → 16-Bit-Pool, einmal das andere Format). Bleibt es schwarz oder nimmt Windows das
## Fenster nicht an, versucht Uzai einmal den Spiegel: Windows zeichnet das Spiel per
## DWM-Vorschau in ein unsichtbares Helferfenster unter Uzai, aufgenommen wird dieses („spiegel“). Was
## der Helfer misst (Grafikkarte, HDR, Format und mittlere Farbe des ersten Bilds, Zustand des
## Spielfensters, exklusives Vollbild), steht je Aufnahme einmal in launch.log.

signal bild(img: Image)
signal kein_bild()

const MediaDaten := preload("res://src/core/media_daten.gd")
const Leistung := preload("res://src/room/leistung.gd")
const Zustand := preload("res://src/core/zustand.gd")
## Grafikstufe → [Sekunden zwischen zwei Bildern, Breite in Pixeln, JPEG-Qualität].
const TAKT := { "hoch": [0.5, 640, 72], "mittel": [0.8, 512, 70], "leicht": [2.0, 320, 62] }
## Weg 1 (Windows Graphics Capture): Grafikstufe → [Bilder je Sekunde, größte Breite, größte Höhe].
## Mehr als 30 bringt im kleinen Fernseher nichts und kostet Spiel und Zimmer Zeit (Kopie auf die CPU).
const FANG := { "hoch": [30, 960, 540], "mittel": [30, 960, 540], "leicht": [20, 640, 360] }
const FANG_PULS_S := 4.0           ## so oft sagt Uzai „weiter“ (der Helfer hört nach 15 s ohne auf)
const FANG_AUS_S := 1.5            ## so lange nicht im Bild → Aufnahme aus
const FANG_WARTE_S := 2.5          ## so lange ohne erstes Bild → „kein Bild“ (exklusives Vollbild …)
const FANG_VERSUCHE := 2           ## so viele Fehlstarts, dann Rückfall auf PrintWindow
## Kopf der Zwischendatei (UzTvFang im Helfer): 32 Byte, „UZTV“, Version 1, Folgenummer, Breite,
## Höhe, Zeilenlänge, Länge; danach RGBA. Feste Grenzen – größere Angaben nimmt Uzai nicht an.
const FANG_KOPF := 32
const FANG_MAGIC := 0x56545A55
const FANG_FARBE_GUELTIG := 0x80000000   ## Feld 28: mittlere Farbe des Bilds (vom Helfer gerechnet)
const FANG_MAX_SEITE := 1280
const FANG_MAX_PX := 1280 * 720
const FARBE_S := 0.3               ## mittlere Farbe (Licht, „schwarz?“) höchstens so oft
const MAX_B64 := 600 * 1024        ## längere Antworten nimmt Uzai gar nicht erst an
const MAX_PX := 1280
const PAUSE_FEHLER := 4.0          ## nach einem Fehler so lange warten (Helfer nicht bedrängen)

## Nur für Proben in der Demo: ein festes Bild statt des Helfers (nie außerhalb der Demo).
static var demo_bild: Image = null
static var demo_titel := ""

var stufe := "mittel"
var sichtbar: Callable                ## → bool: Fernseher im Bild und Zimmer vorn
var letztes: Image                    ## das letzte gute Bild (nur im Speicher)
var _warte := 0.0
var _unterwegs := false
var _pausiert_gefragt := false
var _schwarz := 0
var _gross := false                   ## nächstes Bild groß (für den Übergang ins Vollbild)
## Weg der Aufnahme (launch.log, Proben): "" noch offen, "wgc" (Windows Graphics Capture, auch als Spiegel) oder
## "printwindow" (Rückfall, langsam). Gilt je Spiel: ohne laufendes Spiel wieder offen (_je_spiel_neu).
const ZUSTAENDE_WEG := { "*": [""], "": ["wgc", "printwindow"], "wgc": ["printwindow"], "printwindow": [] }
var weg := "":
	set(neu):
		Zustand.wechsel("zimmer.fernsehbild", ZUSTAENDE_WEG, weg, neu)
		weg = neu
var _pruef_ms := -100000
var _fang_an := false
var _fang_unterwegs := false
var _fang_hwnd := 0
var _fang_fps := 0
var _fang_datei := ""
var _fang_fa: FileAccess
var _fang_seq := -1
var _fang_img: Image
var _fang_puls := 0.0
var _fang_takt := 0.0
var _fang_pause := 0.0
var _fang_seit := 0.0
var _fang_weg_s := 0.0
var _fang_fehler := 0
var _fang_leer_gemeldet := false
var _fang_erstes := false             ## erstes Bild dieser Aufnahme schon im launch.log
var _fang_start_ms := 0
var _fang_farbe := -1                 ## mittlere Farbe des zuletzt gelesenen Bilds (Helfer), -1 unbekannt
var _fang_messung := false            ## Messwerte des Helfers zum ersten Bild schon im launch.log
var _fang_ms_gemeldet := false        ## Zeit des Helfers je Bild schon im launch.log
## Rückfall Spiegel (Helfer: DWM-Vorschau in einem Helferfenster, das aufgenommen wird): gewünscht,
## gerade aktiv, schon einmal versucht (je Spiel einmal).
var spiegel := false
var _fang_spiegel := false
var _spiegel_versucht := false
var _zustand := ""                    ## Zustand des Spielfensters laut Helfer (für launch.log)


## Läuft gerade ein Spiel, das der Fernseher zeigen kann?
static func spiel_laeuft() -> bool:
	return Launcher.in_game or _demo()


static func _demo() -> bool:
	return demo_bild != null and Library.demo


## Titel des laufenden Spiels (für den Fernseher ohne Bild).
static func titel() -> String:
	if _demo():
		return demo_titel
	return Library.display_title(Launcher.current) if Launcher.in_game else ""


func _process(dt: float) -> void:
	var t := Time.get_ticks_usec()
	_schritt(dt)
	Leistung.abschnitt("Spielbild", t)


func _schritt(dt: float) -> void:
	if not spiel_laeuft():
		if _fang_an:
			_fang_aus()
		_je_spiel_neu()
		return
	if fang_moeglich():
		_fang_schritt(dt)
		return
	_warte -= dt
	if _warte > 0.0 or _unterwegs:
		return
	if sichtbar.is_valid() and not bool(sichtbar.call()):
		return
	_holen()


## Kein Spiel (mehr): Weg und Rückfälle gelten je Spiel – das nächste versucht wieder Windows Graphics Capture und
## einmal den Spiegel. Früher blieb ein Zimmer, das offen blieb, nach einem Rückfall auf PrintWindow (etwa ein
## Spiel mit Adminrechten) für jedes weitere Spiel bei PrintWindow: langsam, und es bremste das Spiel.
func _je_spiel_neu() -> void:
	if weg == "" and not spiegel and not _spiegel_versucht and _fang_fehler == 0:
		return
	weg = ""
	spiegel = false
	_spiegel_versucht = false
	_fang_fehler = 0


## Gleich ein neues Bild; gross: einmal in voller Breite (für den Übergang Zimmer ↔ Vollbild, wo
## das Bild kurz den ganzen Bildschirm füllt).
func sofort(gross := false) -> void:
	_warte = 0.0
	_fang_takt = 0.0
	_pruef_ms = -100000
	_gross = _gross or gross


func _holen() -> void:
	var t: Array = TAKT.get(stufe, TAKT.mittel)
	_warte = float(t[0])
	if _demo():
		_neu(demo_bild)
		return
	# Angehalten (Emulator, solange der Guide offen ist): das Bild ändert sich nicht – einmal reicht.
	if Launcher.paused:
		if _pausiert_gefragt:
			return
		_pausiert_gefragt = true
	else:
		_pausiert_gefragt = false
	var hwnd := Launcher.game_hwnd()
	if hwnd == 0 or not Config.is_windows():
		if hwnd == 0:
			_einmal_melden("Fernseher: kein Bild – Uzai kennt kein Spielfenster (%s)" % str(Launcher.current.get("title", "?")))
		kein_bild.emit()
		_warte = PAUSE_FEHLER
		return
	_unterwegs = true
	var breite := MAX_PX if _gross else int(t[1])
	var q := 82 if _gross else int(t[2])
	_gross = false
	var r := await Helper.run("window-frame", { "hwnd": hwnd, "max_w": breite, "q": q }, 4.0)
	_unterwegs = false
	if not is_inside_tree():
		return
	var img := bild_aus(r)
	if img == null:
		_warte = maxf(_warte, PAUSE_FEHLER)
		kein_bild.emit()
		return
	_neu(img)


## farbe: mittlere Farbe als 0xRRGGBB, wenn der Helfer sie schon gerechnet hat (sonst -1).
func _neu(img: Image, farbe := -1) -> void:
	if img == null:
		return
	# Schwarz? Höchstens alle FARBE_S prüfen (bei 30–60 Bildern je Sekunde wäre das sonst teuer) –
	# mit der Farbe des Helfers bei jedem Bild (kostet nichts).
	var jetzt := Time.get_ticks_msec()
	if farbe >= 0 or letztes == null or jetzt - _pruef_ms >= int(FARBE_S * 1000.0):
		if farbe < 0:
			_pruef_ms = jetzt
		var schwarz := farbe_schwarz(farbe) if farbe >= 0 else fast_schwarz(img)
		if schwarz:
			# Mit der Farbe des Helfers zählt jedes Bild: ab gut einer halben Sekunde schwarz.
			_schwarz += 1
			var ab := SCHWARZ_BILDER if farbe >= 0 else 2
			# Einmal an der Schwelle, danach nur noch ab und zu (nicht bei jedem Bild).
			if _schwarz == ab or (_schwarz > ab and _schwarz % ab == 0):
				_nur_schwarz()
			return
		_schwarz = 0
	elif _schwarz > 0:
		return
	letztes = img
	bild.emit(img)


const SCHWARZ_BILDER := 18             ## Bilder mit Farbe vom Helfer: so viele schwarz nacheinander = „schwarz“


## Nur schwarze Bilder: einmal melden (mit dem, was der Helfer über das Fenster weiß), beim direkten
## Weg einmal den Spiegel versuchen, sonst „kein Bild“.
func _nur_schwarz() -> void:
	var wer := "PrintWindow" if weg != "wgc" else ("Windows Graphics Capture (Spiegel)" if _fang_spiegel else "Windows Graphics Capture")
	_einmal_melden("Fernseher: %s liefert nur schwarze Bilder – %s" % [wer, _zustand if _zustand != "" else "exklusives Vollbild oder geschütztes Fenster?"])
	if weg == "wgc" and spiel_weg("schwarz", _fang_spiegel, _spiegel_versucht) == "spiegel":
		_spiegel_an("direkt nur schwarz")
		return
	if weg == "wgc" and _fang_spiegel:
		_einmal_melden("Fernseher: auch der Spiegel (DWM-Vorschau) bleibt schwarz – Windows bekommt vom Spiel gerade kein Bild")
	kein_bild.emit()


## Rückfall Spiegel einschalten (je Spiel einmal); die Aufnahme startet beim nächsten Schritt neu.
func _spiegel_an(warum: String) -> void:
	_spiegel_versucht = true
	spiegel = true
	_schwarz = 0
	_fang_pause = 0.0
	Launcher.log_launch("Fernseher: %s – Rückfall: Windows zeichnet das Spiel in ein Helferfenster (Spiegel), aufgenommen wird dieses" % warum)


## Welcher Weg nach einem Problem mit Weg 1? "spiegel" (einmal versuchen) oder "" (wie bisher).
## grund: „schwarz“ oder der Fehler des Helfers; spiegel_an: läuft schon gespiegelt.
static func spiel_weg(grund: String, spiegel_an: bool, versucht: bool) -> String:
	if spiegel_an or versucht:
		return ""
	if grund == "schwarz" or grund.begins_with("Fenster ") or grund == "Fenster":
		return "spiegel"
	return ""


## Fast schwarz (wie fast_schwarz), aus der Farbe 0xRRGGBB des Helfers.
static func farbe_schwarz(c: int) -> bool:
	if c < 0:
		return false
	return Color8((c >> 16) & 255, (c >> 8) & 255, c & 255).get_luminance() < 0.012


## Messwerte des Helfers (tv-fang) einmal je Aufnahme ins launch.log: Grafikkarte/HDR, Zustand des
## Spielfensters, erstes Bild (Format, Größe, mittlere Farbe), Formatwechsel, Zeit je Bild.
func _messwerte(res: Dictionary) -> void:
	if res.is_empty():
		return
	var z := str(res.get("zustand", "")).left(300)
	if z != "":
		_zustand = z
	var info := str(res.get("info", "")).left(300)
	if info != "":
		_einmal_melden("Fernseher: Aufnahme – " + info)
	if z != "":
		_einmal_melden("Fernseher: Spielfenster – " + z)
	var erstes := str(res.get("erstes", "")).left(300)
	if erstes != "" and not _fang_messung:
		_fang_messung = true
		Launcher.log_launch("Fernseher: erstes Bild vom Helfer – %s; Helfer je Bild %.1f ms" % [erstes, float(res.get("ms", 0.0))])
	if int(res.get("bilder", 0)) >= 150 and not _fang_ms_gemeldet:
		_fang_ms_gemeldet = true
		Launcher.log_launch("Fernseher: Helfer je Bild Ø %.2f ms (Kopie von der Grafikkarte, Umrechnen, Zwischendatei; %d Bilder, Format %s)" % [
				float(res.get("ms", 0.0)), int(res.get("bilder", 0)), str(res.get("format", "?"))])
	var wechsel := str(res.get("wechsel", "")).left(200)
	if wechsel != "":
		_einmal_melden("Fernseher: Helfer hat " + wechsel)


# --- Weg 1: Windows Graphics Capture (Helfer „tv-fang“) ------------------------------------------

## Geht Weg 1 hier (Windows, Helfer da, nicht schon auf den Rückfall gewechselt)?
func fang_moeglich() -> bool:
	return not _demo() and weg != "printwindow" and Config.is_windows() and Helper.available


## Bilder je Sekunde für diese Stufe.
static func fang_fps(st: String) -> int:
	return int((FANG.get(st, FANG.mittel) as Array)[0])


## Argumente für den Helfer (nur Zahlen).
func _fang_args(hwnd: int, fps: int) -> Dictionary:
	var f: Array = FANG.get(stufe, FANG.mittel)
	var a := { "an": true, "spiel": hwnd, "max_w": int(f[1]), "max_h": int(f[2]), "fps": fps }
	if Launcher.filter_pid() > 0:
		a["quelle"] = Launcher.filter_pid()
	if spiegel:
		a["spiegel"] = true
		a["hwnd"] = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	return a


func _fang_schritt(dt: float) -> void:
	if sichtbar.is_valid() and not bool(sichtbar.call()):
		_fang_weg_s += dt
		if _fang_an and _fang_weg_s > FANG_AUS_S:
			_einmal_melden("Fernseher: nicht im Bild (Blickrichtung oder Ebene darüber) – Aufnahme ruht")
			_fang_aus()
		return
	_fang_weg_s = 0.0
	if _fang_unterwegs:
		return
	_fang_pause -= dt
	if _fang_pause > 0.0:
		return
	var hwnd := Launcher.game_hwnd()
	if hwnd == 0:
		if _fang_an:
			_fang_aus()
		_einmal_melden("Fernseher: kein Bild – Uzai kennt kein Spielfenster (%s, Quelle %s)" % [
				str(Launcher.current.get("title", "?")), str(Launcher.current.get("source", "?"))])
		kein_bild.emit()
		_fang_pause = PAUSE_FEHLER
		return
	var fps := fang_fps(stufe)
	if not _fang_an or hwnd != _fang_hwnd or fps != _fang_fps or spiegel != _fang_spiegel:
		_fang_start(hwnd, fps)
		return
	_fang_puls -= dt
	if _fang_puls <= 0.0:
		_fang_puls = FANG_PULS_S
		_fang_weiter(hwnd, fps)
	_fang_seit += dt
	if _fang_seq < 0 and _fang_seit > FANG_WARTE_S and not _fang_leer_gemeldet and not Launcher.paused:
		_fang_leer_gemeldet = true
		_einmal_melden("Fernseher: Aufnahme gestartet, aber nach %.0f s noch kein Bild (Fenster %d, %d Bilder/s, Datei %s)" % [_fang_seit,
				hwnd, fps, "offen" if _fang_fa != null else "nicht lesbar"])
		kein_bild.emit()
	elif _fang_seq < 0 and _fang_seit > FANG_WARTE_S and Launcher.paused:
		_einmal_melden("Fernseher: noch kein Bild – das Spiel ist angehalten")
	_fang_takt -= dt
	if _fang_takt > 0.0:
		return
	# Doppelt so oft nachsehen, wie Bilder kommen (der Kopf sind 32 Byte): kaum Verzögerung.
	_fang_takt = 0.5 / float(maxi(1, fps))
	_fang_lesen()


func _fang_start(hwnd: int, fps: int) -> void:
	_fang_unterwegs = true
	if _fang_fa:
		_fang_fa.close()
		_fang_fa = null
	var r := await Helper.run("tv-fang", _fang_args(hwnd, fps), 5.0)
	_fang_unterwegs = false
	if not is_inside_tree():
		Helper.run("tv-fang", { "an": false })
		return
	var res: Dictionary = r.result if r.get("ok", false) and r.get("result") is Dictionary else {}
	var datei := str(res.get("datei", ""))
	if bool(res.get("an", false)) and datei_ok(datei):
		var neu := weg != "wgc" or fps != _fang_fps or spiegel != _fang_spiegel
		_fang_spiegel = spiegel
		_fang_an = true
		_fang_hwnd = hwnd
		_fang_fps = fps
		_fang_datei = datei
		_fang_seq = -1
		_fang_seit = 0.0
		_fang_takt = 0.0
		_fang_puls = FANG_PULS_S
		_fang_fehler = 0
		_fang_leer_gemeldet = false
		_fang_erstes = false
		_fang_messung = false
		_fang_ms_gemeldet = false
		_fang_farbe = -1
		_fang_start_ms = Time.get_ticks_msec()
		weg = "wgc"
		_messwerte(res)
		if neu:
			var f: Array = FANG.get(stufe, FANG.mittel)
			Launcher.log_launch("Fernseher: Live-Bild über Windows Graphics Capture%s – bis %d×%d, %d Bilder/s, gelber Rahmen %s" % [
					" (Spiegel)" if spiegel else "", int(f[1]), int(f[2]), fps, "aus" if bool(res.get("rand_aus", false)) else "nicht abschaltbar"])
		return
	_fang_an = false
	_fang_fehler += 1
	var grund := str(res.get("grund", r.get("error", "keine Antwort"))).left(160)
	_messwerte(res)
	# Windows nimmt das Spielfenster nicht an (z. B. „Fenster 80070057“): erst der Spiegel, dann PrintWindow.
	if spiel_weg(grund, spiegel, _spiegel_versucht) == "spiegel":
		_spiegel_an("Windows Graphics Capture nimmt das Spielfenster nicht an (%s)" % grund)
		return
	if spiegel:
		# Der Spiegel ging nicht: wieder direkt (beim nächsten Fehlschlag dann PrintWindow).
		spiegel = false
		Launcher.log_launch("Fernseher: Spiegel geht nicht (%s) – wieder direkt" % grund)
		_fang_pause = PAUSE_FEHLER
		return
	if _fang_fehler >= FANG_VERSUCHE or grund in ["nicht unterstützt", "daten"]:
		weg = "printwindow"
		Launcher.log_launch("Fernseher: Windows Graphics Capture geht nicht (%s) – Rückfall auf PrintWindow, langsam (alle %.2f s)" % [grund,
				float((TAKT.get(stufe, TAKT.mittel) as Array)[0])])
	else:
		_fang_pause = PAUSE_FEHLER


## Lebenszeichen an den Helfer; meldet er „aus“ (Fenster zu, Fehler), beim nächsten Schritt neu.
func _fang_weiter(hwnd: int, fps: int) -> void:
	var r := await Helper.run("tv-fang", _fang_args(hwnd, fps), 5.0)
	if not is_inside_tree() or not _fang_an:
		return
	var res: Dictionary = r.result if r.get("ok", false) and r.get("result") is Dictionary else {}
	_messwerte(res)
	if not bool(res.get("an", false)):
		_fang_an = false
		if _fang_fa:
			_fang_fa.close()
			_fang_fa = null


func _fang_lesen() -> void:
	if _fang_fa == null:
		_fang_fa = FileAccess.open(_fang_datei, FileAccess.READ)
		if _fang_fa == null:
			_einmal_melden("Fernseher: Zwischendatei nicht lesbar – %s" % error_string(FileAccess.get_open_error()))
			return
	_frisch(0)
	var kopf := kopf_aus(_fang_fa.get_buffer(FANG_KOPF), _fang_fa.get_length())
	if kopf.is_empty() or int(kopf.seq) == _fang_seq:
		return
	var px := _fang_fa.get_buffer(int(kopf.len))
	_frisch(8)
	# Folgenummer nach dem Lesen noch dieselbe: Das Bild ist ganz (sonst schrieb der Helfer gerade).
	if _fang_fa.get_32() != int(kopf.seq) or px.size() != int(kopf.len):
		return
	_fang_seq = int(kopf.seq)
	_fang_farbe = int(kopf.get("farbe", -1))
	var w := int(kopf.w)
	var h := int(kopf.h)
	if not _fang_erstes:
		_fang_erstes = true
		Launcher.log_launch("Fernseher: erstes Live-Bild nach %d ms (%d×%d)" % [Time.get_ticks_msec() - _fang_start_ms, w, h])
	if _fang_img == null or _fang_img.get_width() != w or _fang_img.get_height() != h:
		_fang_img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, px)
	else:
		_fang_img.set_data(w, h, false, Image.FORMAT_RGBA8, px)
	_neu(_fang_img, _fang_farbe)


## An diese Stelle springen und wirklich neu lesen: Die C-Bibliothek unter FileAccess springt innerhalb
## ihres Puffers nur im Speicher (dann sähe Uzai den alten Kopf). Erst ans Ende (anderer Block), dann zurück.
func _frisch(pos: int) -> void:
	var n := _fang_fa.get_length()
	if n > 4096 * 2:
		_fang_fa.seek(n - 1)
		_fang_fa.get_8()
	else:
		_fang_fa.seek(n)
	_fang_fa.seek(pos)


func _fang_aus() -> void:
	if _fang_fa:
		_fang_fa.close()
		_fang_fa = null
	_fang_seq = -1
	if _fang_an:
		_fang_an = false
		Helper.run("tv-fang", { "an": false })


## Kopf der Zwischendatei → { seq, w, h, len } oder {} (ungültig, wird gerade geschrieben, noch leer).
## laenge: Größe der Datei (Pixel müssen hineinpassen), -1 ohne Prüfung.
static func kopf_aus(k: PackedByteArray, laenge: int) -> Dictionary:
	if k.size() < FANG_KOPF or k.decode_u32(0) != FANG_MAGIC or k.decode_u32(4) != 1:
		return {}
	var seq := k.decode_u32(8)
	if seq == 0 or seq % 2 == 1:
		return {}
	var w := k.decode_u32(12)
	var h := k.decode_u32(16)
	if w < 1 or h < 1 or w > FANG_MAX_SEITE or h > FANG_MAX_SEITE or w * h > FANG_MAX_PX:
		return {}
	if k.decode_u32(20) != w * 4 or k.decode_u32(24) != w * h * 4:
		return {}
	if laenge >= 0 and FANG_KOPF + w * h * 4 > laenge:
		return {}
	var c := k.decode_u32(28)
	return { "seq": seq, "w": w, "h": h, "len": w * h * 4, "farbe": (c & 0xFFFFFF) if c & FANG_FARBE_GUELTIG else -1 }


## Nur die Zwischendatei des Helfers: absoluter Pfad, fester Name „uzai-tvbild-<Nummer>.bin“.
static func datei_ok(p: String) -> bool:
	var n := p.replace("\\", "/").get_file()
	if p.length() > 400 or p.contains("..") or not (p.begins_with("/") or (p.length() > 3 and p[1] == ":")):
		return false
	return RegEx.create_from_string("^uzai-tvbild-[0-9]{1,10}\\.bin$").search(n) != null


## Antwort des Helfers → Bild, oder null. Streng: Länge, JPEG-Kopf und Größe vor dem Dekodieren.
static func bild_aus(r: Dictionary) -> Image:
	if not bool(r.get("ok", false)) or not (r.get("result") is Dictionary):
		return null
	var res: Dictionary = r.result
	if str(res.get("result", "")) != "ok" or not (res.get("jpg") is String):
		return null
	var b64: String = res.jpg
	if b64.length() < 16 or b64.length() > MAX_B64 or b64.length() % 4 != 0:
		return null
	var b := Marshalls.base64_to_raw(b64)
	var gr := MediaDaten.kopf_groesse(b, "jpg")
	if gr.x <= 0 or gr.y <= 0 or gr.x > MAX_PX or gr.y > MAX_PX:
		return null
	var img := Image.new()
	if img.load_jpg_from_buffer(b) != OK or img.is_empty() or img.get_width() > MAX_PX or img.get_height() > MAX_PX:
		return null
	return img


## Mittlere Farbe (für das Licht, das der Fernseher in den Raum wirft, und „schwarz?“): Mittel aus
## einem Raster von 16 × 9 Punkten (Mitte jedes Felds). Früher ein Bild auf 4 × 4 verkleinert – das
## nahm nur 16 Stellen (bilinear liest beim Verkleinern nur Nachbarn) und kopierte das ganze Bild.
static func mittelfarbe(img: Image) -> Color:
	if img == null or img.is_empty():
		return Color.BLACK
	var w := img.get_width()
	var h := img.get_height()
	var nx := mini(16, w)
	var ny := mini(9, h)
	var s := Color(0, 0, 0, 0)
	for j in ny:
		var y := mini(h - 1, int((j + 0.5) * h / ny))
		for i in nx:
			s += img.get_pixel(mini(w - 1, int((i + 0.5) * w / nx)), y)
	var n := float(nx * ny)
	return Color(s.r / n, s.g / n, s.b / n)


## Eine Zeile ins launch.log, je Text nur einmal je Spiel (keine Flut alle paar Sekunden).
var _gemeldet := {}


func _einmal_melden(text: String) -> void:
	var k := text + "|" + str(Launcher.current.get("id", ""))
	if _gemeldet.has(k):
		return
	_gemeldet[k] = true
	Launcher.log_launch(text)


static func fast_schwarz(img: Image) -> bool:
	return mittelfarbe(img).get_luminance() < 0.012


func _exit_tree() -> void:
	_fang_aus()
	letztes = null

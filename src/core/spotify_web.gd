extends Node
## „Mit Spotify anmelden“: die Spotify-Sitzung über Uzais Browser-Kern (helper/uzai-browser-kern.cs im Modus
## „--uzai-spotify“, docs/BROWSER_PLAN.md 8). Einmal erscheint die echte Anmeldeseite (accounts.spotify.com) im
## Uzai-Browser (browser.gd mit spotify = true, src/ui/layers/spotify_anmelden.gd) – mit Controller, Uzai-Tastatur und
## allen Wegen, die Spotify dort selbst anbietet (Passwort, Code per Mail, Passkey). Danach lädt der Kern bei Bedarf
## unsichtbar den Webplayer (open.spotify.com); der Kern liest den Zugriffsschlüssel aus den eigenen Anfragen der Seite
## an pathfinder/spclient (Kopfzeile „Authorization“, dazu „client-token“ und die Fassung) und meldet ihn über die
## Leitung (Ereignis „spotify“). Uzai berechnet keinen Schlüssel selbst (kein Nachbau von get_access_token/TOTP) –
## erneuern tut ihn die Seite selbst.
## Abfragen (abfrage()): Uzai fragt Spotify nicht selbst, sondern lässt den Kern IN der angemeldeten Seite fragen
## (Befehl „spotify-abfrage“ → fetch() im Seitenkontext mit den Kopfzeilen der Seite → Ereignis „spotify-antwort“).
## Für Spotify sieht so jede Anfrage aus wie vom Webplayer (am PC des Nutzers lehnte pathfinder Uzais eigene
## HTTP-Anfragen mit 403 ab, obwohl der Schlüssel stimmte). Uzai nennt nur Ziel-Art (pathfinder, spclient, webapi),
## Methode, Pfad und Inhalt – Host und Kopfzeilen setzt der Kern; beide Seiten prüfen dieselben Regeln
## (browser_protokoll.gd spotify_abfrage_grund). Der Kern bleibt offen, solange Abfragen kommen, und geht nach
## LEERLAUF_S ohne Abfrage zu. music_spotify.gd (_netz) leitet alle Abrufe der Spotify-Sitzung hierher.
##
## Sicherheit: eigener Datenordner (%LOCALAPPDATA%\Uzai\browser\spotify-daten\profil\<profil>, getrennt vom Browser),
## Hauptrahmen nur zu Spotify und den Anmeldediensten seiner Anmeldeseite (Kern und hier dieselbe Liste), kein Blocker,
## keine Downloads, keine Rechte, die Seite meldet sich nie als Connect-Gerät an und bleibt stumm. Die Anmeldung
## (Cookies) liegt nur in diesem Ordner – Chromium verschlüsselt sie mit DPAPI; Uzai speichert selbst nur, DASS
## angemeldet ist (accounts.spotify_web). Den Schlüssel hält Uzai nur im Speicher, nie in Einstellungen oder
## Protokollen. „Abmelden“ beendet den Kern und löscht den ganzen Ordner.
## Fällt etwas aus (kein Schlüssel in WARTEN_S, Kern startet nicht), meldet holen() den Grund – Music geht dann in
## den Grundmodus (Läuft gerade über die Mediensitzung bzw. Spotify Connect), nichts wartet länger.

const Fremd := preload("res://src/core/fremd.gd")

signal fertig                   ## ein holen() ist zu Ende (alle Wartenden bekommen dasselbe Ergebnis)

const P := preload("res://src/core/browser_protokoll.gd")
const Wirt := preload("res://src/core/browser_wirt.gd")
const Zustand := preload("res://src/core/zustand.gd")

const ANMELDEN_URL := "https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F"
const WEB_URL := "https://open.spotify.com/"
## Anmeldedienste, die Spotifys Anmeldeseite selbst anbietet (wie UzcSpotify.ANMELDUNG im Kern).
const ANMELDUNG := ["accounts.google.com", "appleid.apple.com", "www.facebook.com", "m.facebook.com"]
const GILT_S := 50 * 60         ## so lange nimmt Uzai einen Schlüssel der Seite (Spotify gibt ihn für eine Stunde)
const WARTEN_S := 30.0          ## so lange wartet ein Abruf höchstens auf die Seite
const MAX_SCHLUESSEL := 2048
const ABFRAGE_S := 20.0         ## Zeitlimit je Abfrage in der Seite (der Kern bricht fetch() dann ab)
const LEERLAUF_S := 120.0       ## so lange ohne Abfrage bleibt der Kern offen, dann geht er zu
const GLEICHZEITIG := 4         ## höchstens so viele Abfragen gleichzeitig in der Seite (die übrigen warten kurz)
const KERN_PAUSE_S := 60.0      ## gab der Kern keinen Schlüssel: so lange schlagen Abfragen sofort fehl (nichts wartet)
const FRISCH_S := GILT_S - 600  ## so jung muss der letzte Schlüssel der laufenden Seite sein, damit holen() ihn nimmt

signal schluessel_neu           ## die Seite hat einen (neuen) Schlüssel gemeldet

## Tests und Netz-Probe: statt des Kerns ein Callable, das { ok, token, client, version, why } liefert.
var quelle := Callable()
## Protokoll (Music._log): nur Zustände, nie Werte.
var log_fn := Callable()
## Die Anmeldeseite ist gerade offen (eigener Kern auf demselben Ordner): kein zweiter Kern.
var anmeldung_offen := false
## Wirt der offenen Anmeldeseite (browser.gd): solange sie läuft, gehen Abfragen dorthin (derselbe Ordner).
var anmelde_wirt: Node = null
## Tests: statt der Seite ein Callable (ziel, methode, pfad, inhalt) -> { code, text, grund, gekuerzt, warte }.
var abfrage_quelle := Callable()
## Tests: kürzerer Leerlauf bzw. kürzeres Warten auf das Ende der Anmeldeseite.
var leerlauf_s := LEERLAUF_S
var anmeldung_warten_s := 10.0

var _wirt: Wirt = null
var _laeuft := false
var _ergebnis := {}
var _zu_gen := 0
var _offen := {}                ## Kennung -> { done, r, wirt } (laufende Abfragen)
var _id := 0
var _aktiv := 0                 ## gerade laufende Abfragen
var _letzte_ms := 0             ## letzte Abfrage (für den Leerlauf)
var _letzter := {}              ## zuletzt gemeldeter Schlüssel der laufenden Seite { token, client, version }
var _schluessel_ms := -1        ## wann (ms); -1 = in diesem Kern noch keiner
var _kern_aus_bis := 0          ## ms: bis dahin keine Abfrage über einen neuen Kern
var _leer_gen := 0
var _verworfen := ""            ## diesen Schlüssel hat Spotify abgelehnt: holen() gibt ihn nicht noch einmal heraus
var _diag := {}                 ## Abfrage-Art -> letzter Code (Protokoll nur bei Änderung)
var _kopf_diag := ""


# --- Regeln (statisch, getestet) -------------------------------------------------------------------

static var _RX_FASSUNG_TEIL := RegEx.create_from_string("^v[0-9]{1,2}\\z")
static var _RX_MAIL := RegEx.create_from_string("\\S+@\\S+")
static var _RX_URI := RegEx.create_from_string("spotify:[A-Za-z]+:[A-Za-z0-9]+")
static var _RX_LANG := RegEx.create_from_string("[A-Za-z0-9_+/=.-]{16,}")
static var _RX_STEUER := RegEx.create_from_string("[\\x00-\\x1f\\x7f]+")

static func host_erlaubt(h: String) -> bool:
	if h == "" or h.length() > 253:
		return false
	return h == "spotify.com" or h.ends_with(".spotify.com") or h in ANMELDUNG


## Darf der Hauptrahmen der Spotify-Sitzung dorthin? Nur https, nur Spotify und seine Anmeldedienste.
static func erlaubt(url: String) -> bool:
	if not url.begins_with("https://") or url.length() > 4096 or P.Adresse.grund(url, false) != "":
		return false
	return host_erlaubt(url.substr(8).get_slice("/", 0).get_slice("?", 0).get_slice("#", 0).get_slice(":", 0).to_lower())


## Zweite Mauer: ein Ereignis „spotify“ des Kerns → { token, client, version } oder {} (kaputt).
static func aus_ereignis(e: Dictionary) -> Dictionary:
	if str(e.get("t", "")) != "spotify":
		return {}
	var tok := str(e.get("token", ""))
	var ct := str(e.get("client", ""))
	var fa := str(e.get("version", ""))
	if tok.length() < 20 or tok.length() > MAX_SCHLUESSEL or not P.schluessel_ok(tok):
		return {}
	if ct != "" and (ct.length() < 20 or ct.length() > MAX_SCHLUESSEL or not P.schluessel_ok(ct)):
		ct = ""
	if not fassung_ok(fa):
		fa = ""
	return { "token": tok, "client": ct, "version": fa }


## Zweite Mauer für „spotify-antwort“: { id, code, grund, text, gekuerzt, warte } oder {} (kaputt).
static func aus_antwort(e: Dictionary) -> Dictionary:
	if str(e.get("t", "")) != "spotify-antwort":
		return {}
	var id: Variant = e.get("id")
	var code: Variant = e.get("code")
	var warte: Variant = e.get("warte")
	var text: Variant = e.get("text")
	if not (id is int) or not (code is int) or int(code) < 0 or int(code) > 999 or not (warte is int) or int(warte) < 0 or int(warte) > 86400:
		return {}
	if not (text is String) or (text as String).length() > P.MAX_ANTWORT or not (e.get("gekuerzt") is bool) or not str(e.get("grund", "?")) in P.SPOTIFY_GRUENDE:
		return {}
	return { "id": int(id), "code": int(code), "grund": str(e.grund), "text": text, "gekuerzt": bool(e.gekuerzt), "warte": int(warte) }


## Art einer Abfrage fürs Protokoll, ohne Kennungen: „libraryV3“, „connect-state/devices“, „/v1/me/playlists“.
static func art_von(ziel: String, pfad: String, inhalt: String) -> String:
	if ziel == "pathfinder":
		var b: Variant = Fremd.json_roh(inhalt) if inhalt != "" else null
		return str((b as Dictionary).get("operationName", "?")).left(64) if b is Dictionary else "?"
	var teile: Array = []
	for t in pfad.get_slice("?", 0).split("/", false):
		if teile.size() >= (3 if ziel == "webapi" else 2):
			break
		if ziel == "spclient" and _RX_FASSUNG_TEIL.search(t) != null:
			continue
		teile.append("…" if (t.length() >= 16 or t.contains(":") or t.contains("%")) else t)
	return ("/" if ziel == "webapi" else "") + "/".join(teile)


## Anfang eines Fehlertexts fürs Protokoll: höchstens 120 Zeichen, ohne alles, was wie Schlüssel, Kennung oder
## Adresse aussieht (lange Zeichenfolgen, spotify:-Adressen, E-Mail), ohne Steuerzeichen.
static func fehler_kurz(text: String) -> String:
	var t := text.left(600)
	t = _RX_MAIL.sub(t, "…@…", true)
	t = _RX_URI.sub(t, "spotify:…", true)
	t = _RX_LANG.sub(t, "…", true)
	t = _RX_STEUER.sub(t, " ", true)
	return t.strip_edges().left(120)


## Welche Kopfzeilen die Seite mitschickt (fürs Protokoll, nie die Werte).
static func kopf_text(w: Dictionary) -> String:
	return "Schlüssel %s, client-token %s, Fassung %s" % ["ja" if str(w.get("token", "")) != "" else "nein",
		"ja" if str(w.get("client", "")) != "" else "nein", "ja" if str(w.get("version", "")) != "" else "nein"]


static func fassung_ok(v: String) -> bool:
	if v.length() < 3 or v.length() > 40 or not (v[0] >= "0" and v[0] <= "9"):
		return false
	for c in v:
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "z") or c == "."):
			return false
	return true


## Ist die Anmeldung durch? Die Seite steht wieder auf dem Webplayer (open.spotify.com), nicht mehr auf accounts.
static func nach_anmeldung(url: String) -> bool:
	if not url.begins_with("https://"):
		return false
	var h := url.substr(8).get_slice("/", 0).get_slice("?", 0).to_lower()
	return h == "open.spotify.com"


## Steht die Seite nach dem Laden auf der Anmeldung? Dann gilt die Sitzung nicht mehr (abgemeldet, abgelaufen).
static func auf_anmeldung(url: String) -> bool:
	if not url.begins_with("https://"):
		return false
	var rest := url.substr(8)
	var h := rest.get_slice("/", 0).to_lower()
	var pfad := rest.substr(h.length()).get_slice("?", 0).get_slice("#", 0).to_lower()
	return h == "accounts.spotify.com" and pfad.contains("/login")


## Ordner der Sitzung (nur Windows; sonst ""): %LOCALAPPDATA%\Uzai\browser\spotify-daten\profil\<profil>.
static func ordner() -> String:
	var lokal := OS.get_environment("LOCALAPPDATA")
	if lokal.length() < 3:
		return ""
	return lokal.replace("\\", "/").path_join("Uzai/browser/spotify-daten/profil").path_join(Wirt._profil())


## Löscht einen Sitzungsordner ganz. Nur Pfade unter …/Uzai/browser/spotify-daten/profil/<kennung> (Schutz gegen
## falsche Pfade); true, wenn danach nichts mehr da ist.
static func ordner_loeschen(dir: String) -> bool:
	var d := dir.replace("\\", "/").trim_suffix("/")
	var muster := RegEx.create_from_string("/Uzai/browser/spotify-daten/profil/[a-z0-9_-]{1,40}\\z")
	if d.contains("..") or muster.search(d) == null:
		return false
	if not DirAccess.dir_exists_absolute(d):
		return true
	_leeren(d, 0)
	DirAccess.remove_absolute(d)
	return not DirAccess.dir_exists_absolute(d)


static func _leeren(d: String, tiefe: int) -> void:
	if tiefe > 24:
		return
	var da := DirAccess.open(d)
	if da == null:
		return
	da.include_hidden = true
	for f in da.get_files():
		DirAccess.remove_absolute(d.path_join(f))
	for sub in da.get_directories():
		# Nie durch eine Verknüpfung hindurch löschen (nur die Verknüpfung selbst).
		if not da.is_link(sub):
			_leeren(d.path_join(sub), tiefe + 1)
		DirAccess.remove_absolute(d.path_join(sub))


# --- Schlüssel holen ---------------------------------------------------------------------------------

## Läuft gerade ein Kern der Sitzung (unsichtbar)?
func laeuft() -> bool:
	return is_instance_valid(_wirt) and _wirt.laeuft()


## Einen frischen Schlüssel von der Seite: { ok, token, client, version } oder { ok: false, why } mit why
## "abgemeldet" (die Seite steht auf der Anmeldung), "kern" (Kern startet nicht), "zeit" (kein Schlüssel in
## WARTEN_S), "anmeldung" (die Anmeldeseite ist gerade offen). Nur ein Lauf gleichzeitig, alle bekommen dasselbe.
## Stand „musik.sitzung“ für Zustand.lage() und den Fehlerbericht: holt, dann schluessel oder der Grund (kein Feld:
## gemeldet, wo ein Lauf beginnt und endet).
func holen(warten := WARTEN_S) -> Dictionary:
	if quelle.is_valid():
		var r: Variant = await quelle.call()
		return r if r is Dictionary else { "ok": false, "why": "zeit" }
	if anmeldung_offen:
		return { "ok": false, "why": "anmeldung" }
	if _laeuft:
		await fertig
		return _ergebnis.duplicate()
	# Die Seite läuft schon (Abfragen) und erneuert ihren Schlüssel selbst: einen jungen gleich nehmen –
	# außer Spotify hat genau diesen eben abgelehnt (schluessel_verwerfen): dann lädt die Seite neu.
	if laeuft() and _wirt.bereit and not _letzter.is_empty() and _schluessel_ms >= 0 and Time.get_ticks_msec() - _schluessel_ms < int(FRISCH_S * 1000.0) \
			and str(_letzter.get("token", "")) != _verworfen:
		_leerlauf()
		return { "ok": true, "token": _letzter.token, "client": _letzter.client, "version": _letzter.version }
	_laeuft = true
	_ergebnis = {}
	# Der Lauf steht in einer eigenen Funktion: Bricht er mit einem Fehler ab, werden die Wartenden hier trotzdem
	# geweckt. Sonst warteten sie – und mit ihnen jede spätere Anfrage an Spotify – bis zum Neustart.
	await _holen_lauf(warten)
	if _ergebnis.is_empty():
		_ergebnis = { "ok": false, "why": "zeit" }
	var gut: bool = _ergebnis.get("ok", false) == true
	Zustand.melden("musik.sitzung", "schluessel" if gut else str(_ergebnis.get("why", "?")))
	_laeuft = false
	fertig.emit()
	if gut:
		_leerlauf()
	else:
		_spaeter_zu(0.0)
	return _ergebnis.duplicate()


## Spotify hat diesen Schlüssel abgelehnt (der Dealer nimmt keine älteren, siehe music_spotify.gd): Der nächste
## holen() lädt die Seite neu und bringt einen frischen, statt denselben noch einmal herauszugeben. Abfragen in der
## Seite laufen davon unberührt weiter.
func schluessel_verwerfen(token: String) -> void:
	if token != "":
		_verworfen = token


## Der Lauf von holen(): Kern starten bzw. die Seite neu laden und auf den Schlüssel warten (_ergebnis).
func _holen_lauf(warten: float) -> void:
	Zustand.melden("musik.sitzung", "holt")
	_zu_gen += 1
	var t0 := Time.get_ticks_msec()
	if not laeuft():
		_starten()
	elif _wirt.bereit:
		# Läuft noch (Nachlauf): die Seite neu laden – sie holt sich dabei einen neuen Schlüssel.
		_wirt.senden("tab-neu", { "url": WEB_URL, "privat": false, "vorn": true, "nutzer": false })
	while _ergebnis.is_empty() and Time.get_ticks_msec() - t0 < int(warten * 1000.0) and is_inside_tree():
		await get_tree().create_timer(0.1).timeout
	_log("Spotify-Sitzung: %s nach %.1f s" % ["Schlüssel da" if _ergebnis.get("ok", false) == true else str(_ergebnis.get("why", "zeit")),
		(Time.get_ticks_msec() - t0) / 1000.0])


func _starten() -> void:
	if is_instance_valid(_wirt):
		_wirt.queue_free()
	_wirt = Wirt.new()
	_wirt.spotify = true
	_wirt.name = "SpotifySitzung"
	add_child(_wirt)
	_wirt.ereignis.connect(_ereignis)
	var w := _wirt
	_schluessel_ms = -1
	_letzter = {}
	_wirt.beendet.connect(func(_g: String) -> void:
		_offene_beenden(w)
		if w == _wirt:
			_schluessel_ms = -1
		if _laeuft and _ergebnis.is_empty():
			_ergebnis = { "ok": false, "why": "kern" })
	_wirt.starten("Spotify-Sitzung")


## Ereignis des eigenen (unsichtbaren) Kerns.
func _ereignis(e: Dictionary) -> void:
	match str(e.get("t", "")):
		"bereit":
			if is_instance_valid(_wirt):
				_wirt.senden("tab-neu", { "url": WEB_URL, "privat": false, "vorn": true, "nutzer": false })
		"spotify":
			var w := aus_ereignis(e)
			if w.is_empty():
				return
			_letzter = w
			_schluessel_ms = Time.get_ticks_msec()
			kopf_melden(w)
			schluessel_neu.emit()
			if _laeuft:
				_ergebnis = { "ok": true, "token": w.token, "client": w.client, "version": w.version }
		"spotify-antwort":
			antwort(e)
		"tab":
			if _laeuft and not bool(e.get("laedt", true)) and auf_anmeldung(str(e.get("url", ""))):
				_ergebnis = { "ok": false, "why": "abgemeldet" }
		"fehler":
			if _laeuft:
				_ergebnis = { "ok": false, "why": "kern" }


func _spaeter_zu(s: float) -> void:
	var gen := _zu_gen
	if s > 0.0 and is_inside_tree():
		await get_tree().create_timer(s).timeout
	if gen == _zu_gen and not _laeuft:
		await stoppen()


## Nach jedem Schlüssel und jeder Abfrage: Der Kern bleibt offen, bis leerlauf_s lang keine Abfrage kam (dann zu,
## damit kein Prozess dauerhaft läuft). Nur eine Wache gleichzeitig.
func _leerlauf() -> void:
	_letzte_ms = Time.get_ticks_msec()
	_leer_gen += 1
	var gen := _leer_gen
	var schritt := clampf(leerlauf_s / 4.0, 0.05, 5.0)
	while gen == _leer_gen and is_inside_tree() and laeuft():
		await get_tree().create_timer(schritt).timeout
		if gen != _leer_gen or not is_inside_tree():
			return
		if _aktiv == 0 and not _laeuft and Time.get_ticks_msec() - _letzte_ms > int(leerlauf_s * 1000.0):
			_log("Spotify-Sitzung: %d s ohne Abfrage, Kern zu" % int(leerlauf_s))
			_zu_gen += 1
			await stoppen()
			return


## Kern der Sitzung beenden (wartet, bis er weg ist – höchstens ein paar Sekunden).
func stoppen() -> void:
	var w := _wirt
	_wirt = null
	_leer_gen += 1
	_schluessel_ms = -1
	_offene_beenden(w)
	if is_instance_valid(w) and w.laeuft():
		await w.beenden("Spotify-Sitzung zu")
	elif is_instance_valid(w):
		w.queue_free()


## Die Anmeldeseite öffnet (browser.gd im Spotify-Modus, eigener Kern auf demselben Ordner): kein zweiter Kern;
## Abfragen laufen, solange sie offen ist, in ihrer Seite (Kontoprüfung gleich nach der Anmeldung).
func anmeldung_start(w: Node) -> void:
	anmeldung_offen = true
	anmelde_wirt = w
	if is_instance_valid(w) and w.has_signal("beendet"):
		w.connect("beendet", func(_g: String) -> void: _offene_beenden(w))


## Die Anmeldeseite ist zu: sobald ihr Kern weg ist (höchstens 8 s), darf die Sitzung wieder einen eigenen starten.
func anmeldung_beendet(w: Node) -> void:
	var bis := Time.get_ticks_msec() + 8000
	while is_instance_valid(w) and w.call("laeuft") and Time.get_ticks_msec() < bis and is_inside_tree():
		await get_tree().create_timer(0.1).timeout
	_offene_beenden(w)
	if anmelde_wirt == w:
		anmelde_wirt = null
	anmeldung_offen = false


# --- Abfragen in der Seite ---------------------------------------------------------------------------

## Ist die Brücke da? Nicht, wenn ein Test die Seite durch ein Callable ersetzt hat (quelle) und keine Abfragen
## nachbaut (dann fragt music_spotify.gd wie früher direkt, gegen den Nachbau im Netz-Test).
func bruecke() -> bool:
	return abfrage_quelle.is_valid() or not quelle.is_valid()


## Eine Abfrage IN der angemeldeten Seite: { code, text, grund, gekuerzt, warte }. code 0 = keine Antwort, grund:
## "ziel" (Regeln), "zeit", "netz", "gross", "welt" (keine Seite, Kern zu), "schluessel" (die Seite hat noch keinen),
## "voll", "anmeldung" (die Anmeldeseite geht gerade zu). Wartet höchstens zeit_s + 3 s (nach dem Start des Kerns).
func abfrage(ziel: String, methode: String, pfad: String, inhalt := "", verbindung := "", zeit_s := ABFRAGE_S) -> Dictionary:
	if P.spotify_abfrage_grund(ziel, methode, pfad, inhalt, verbindung) != "":
		return _fehl("ziel")
	_letzte_ms = Time.get_ticks_msec()
	var r := {}
	if abfrage_quelle.is_valid():
		var v: Variant = await abfrage_quelle.call(ziel, methode, pfad, inhalt)
		var d: Dictionary = v if v is Dictionary else {}
		r = aus_antwort({ "t": "spotify-antwort", "id": 1, "code": d.get("code", 0), "grund": d.get("grund", ""), "text": d.get("text", ""),
			"gekuerzt": d.get("gekuerzt", false), "warte": d.get("warte", 0) })
		if r.is_empty():
			r = _fehl("gross")
	else:
		r = await _in_der_seite(ziel, methode, pfad, inhalt, verbindung, zeit_s)
		if str(r.grund) == "schluessel":
			# Die Seite lädt gerade (neu) und hat noch keinen Schlüssel geschickt: kurz auf ihn warten, einmal nachfassen.
			await _warten_auf_schluessel(10.0)
			r = await _in_der_seite(ziel, methode, pfad, inhalt, verbindung, zeit_s)
		elif str(r.grund) == "welt" and not anmeldung_offen and Time.get_ticks_msec() >= _kern_aus_bis:
			# Der Kern ging eben zu (Anmeldeseite zu, Leerlauf): einmal mit dem eigenen Kern.
			r = await _in_der_seite(ziel, methode, pfad, inhalt, verbindung, zeit_s)
	_letzte_ms = Time.get_ticks_msec()
	_diagnose(ziel, art_von(ziel, pfad, inhalt), r)
	return r


static func _fehl(grund: String) -> Dictionary:
	return { "id": 0, "code": 0, "grund": grund, "text": "", "gekuerzt": false, "warte": 0 }


func _in_der_seite(ziel: String, methode: String, pfad: String, inhalt: String, verbindung: String, zeit_s: float) -> Dictionary:
	var w: Node = await _wirt_fuer_abfrage()
	if w == null:
		return _fehl("welt")
	# Bündeln: höchstens GLEICHZEITIG in der Seite, die übrigen warten (der Kern nimmt ohnehin nicht mehr als 8).
	var bis_platz := Time.get_ticks_msec() + int(zeit_s * 1000.0)
	while _aktiv >= GLEICHZEITIG and Time.get_ticks_msec() < bis_platz and is_inside_tree():
		await get_tree().process_frame
	if _aktiv >= GLEICHZEITIG:
		return _fehl("voll")
	if not is_instance_valid(w) or not w.call("laeuft"):
		return _fehl("welt")
	_aktiv += 1
	_id = _id % 1000000000 + 1
	var id := _id
	var box := { "done": false, "r": {}, "wirt": w }
	_offen[id] = box
	var zeit_ms := clampi(int(zeit_s * 1000.0), 1000, 30000)
	if not w.call("senden", "spotify-abfrage", { "id": id, "ziel": ziel, "methode": methode, "pfad": pfad, "inhalt": inhalt, "verbindung": verbindung,
			"zeit": zeit_ms }):
		box.done = true
		box.r = _fehl("ziel")
	var bis := Time.get_ticks_msec() + zeit_ms + 3000
	while not bool(box.done) and Time.get_ticks_msec() < bis and is_inside_tree():
		await get_tree().process_frame
	_offen.erase(id)
	_aktiv -= 1
	_letzte_ms = Time.get_ticks_msec()
	return box.r if bool(box.done) else _fehl("zeit")


## Welcher Kern fragt: die offene Anmeldeseite (solange sie läuft), sonst der eigene – bei Bedarf gestartet
## (holen() wartet auf den ersten Schlüssel). null, wenn es keinen gibt.
func _wirt_fuer_abfrage() -> Node:
	if anmeldung_offen:
		var aw := anmelde_wirt
		if is_instance_valid(aw) and aw.call("laeuft") and bool(aw.get("bereit")) and not bool(aw.get("_beenden")):
			return aw
		# Die Anmeldeseite geht gerade zu: warten, bis ihr Kern weg ist (anmeldung_beendet), dann der eigene.
		var bis := Time.get_ticks_msec() + int(anmeldung_warten_s * 1000.0)
		while anmeldung_offen and Time.get_ticks_msec() < bis and is_inside_tree():
			await get_tree().create_timer(0.1).timeout
		if anmeldung_offen:
			return null
	if laeuft() and _wirt.bereit and _schluessel_ms >= 0:
		return _wirt
	if Time.get_ticks_msec() < _kern_aus_bis:
		return null
	var h := await holen()
	if not bool(h.get("ok", false)):
		_kern_aus_bis = Time.get_ticks_msec() + int(KERN_PAUSE_S * 1000.0)
		_log("Spotify-Sitzung: keine Seite für Abfragen (%s), %d s Pause" % [str(h.get("why", "?")), int(KERN_PAUSE_S)])
		return null
	return _wirt if laeuft() else null


func _warten_auf_schluessel(s: float) -> void:
	var bis := Time.get_ticks_msec() + int(s * 1000.0)
	var box := { "da": false }
	var cb := func() -> void: box.da = true
	schluessel_neu.connect(cb)
	while not bool(box.da) and Time.get_ticks_msec() < bis and is_inside_tree():
		await get_tree().create_timer(0.1).timeout
	schluessel_neu.disconnect(cb)


## Ereignis „spotify-antwort“ (vom eigenen Kern oder, über browser.gd, von der Anmeldeseite).
func antwort(e: Dictionary) -> void:
	var r := aus_antwort(e)
	if r.is_empty():
		return
	var box: Variant = _offen.get(int(r.id))
	if box is Dictionary and not bool((box as Dictionary).done):
		box.r = r
		box.done = true


## Ein Kern ging zu: seine offenen Abfragen sofort beenden (grund "welt"), nicht erst nach dem Zeitlimit.
func _offene_beenden(w: Variant) -> void:
	for id in _offen.keys():
		var box: Dictionary = _offen[id]
		if not bool(box.done) and (not is_instance_valid(box.wirt) or box.wirt == w):
			box.r = _fehl("welt")
			box.done = true


## Diagnose (logs/spotify.log, ohne Werte): je Abfrage-Art der HTTP-Code, wenn er sich ändert; bei 4xx/5xx der
## gesäuberte Anfang des Fehlertexts; ohne Antwort der Grund. Veraltete persisted-query-Hashes fallen hier auf.
func _diagnose(ziel: String, art: String, r: Dictionary) -> void:
	var code := int(r.get("code", 0))
	# Nur der Anfang: Fehlermeldungen sind kurz, Antworten bis 2 MB – die durchsucht Uzai nicht nach jedem Abruf ganz.
	var text := str(r.get("text", "")).left(4000)
	var schluessel := ziel + " " + art
	var neu := "%d|%s" % [code, str(r.get("grund", ""))]
	if text.contains("PersistedQueryNotFound") or text.contains("persistedQuery"):
		neu += "|hash"
	if str(_diag.get(schluessel, "")) == neu:
		return
	_diag[schluessel] = neu
	if code == 0:
		_log("Seite → %s %s: keine Antwort (%s)" % [ziel, art, str(r.get("grund", "?"))])
		return
	var dazu := ""
	if neu.ends_with("|hash"):
		dazu = " – Hash veraltet (Spotify kennt die Abfrage so nicht mehr)"
	elif code >= 400:
		dazu = " – " + fehler_kurz(text)
	if bool(r.get("gekuerzt", false)):
		dazu += " (gekürzt)"
	_log("Seite → %s %s: HTTP %d%s" % [ziel, art, code, dazu])


## Protokoll: welche Kopfzeilen die Seite schickt (nur ja/nein), wenn es sich ändert.
func kopf_melden(w: Dictionary) -> void:
	var t := kopf_text(w)
	if t != _kopf_diag:
		_kopf_diag = t
		_log("Spotify-Sitzung: Kopfzeilen der Seite – " + t)


## Abmelden: Kern beenden, den Ordner der Sitzung (Cookies, Speicher, Cache) ganz löschen.
func abmelden() -> bool:
	_zu_gen += 1
	await stoppen()
	var d := ordner()
	var ok := d == "" or ordner_loeschen(d)
	_log("Spotify-Sitzung: abgemeldet, Ordner %s" % ("gelöscht" if ok else "nicht ganz gelöscht"))
	return ok


func _log(t: String) -> void:
	if log_fn.is_valid():
		log_fn.call(t)

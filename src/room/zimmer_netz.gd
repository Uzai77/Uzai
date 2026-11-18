extends RefCounted
## Die schmale Leitung zwischen Uzai und dem abgeschotteten Netzwerk-Teil fürs Zimmer
## (docs/PLAN_ZIMMER_ONLINE.md Phase 2; docs/ZIMMER_SICHERHEIT.md W7). Der Netzwerk-Teil läuft als
## eigener Prozess im Windows-AppContainer (helper/uzai-helper.ps1, „-ZimmerNetz“): nur
## „internetClient“, keine Dateien, keine Kindprozesse, Job-Objekt. Uzai spricht mit ihm nur über
## seine Standardeingabe und -ausgabe in festen Rahmen: 4 Byte Länge (little endian), 1 Byte Art,
## Nutzlast bis 8 KiB.
##
## Zwei Prüfmauern: Die Sandbox prüft jede Nachricht der Gegenstelle (Prüfmauer 1, UzNetzSchema)
## und drosselt je Gast; Uzai prüft, was durchkommt, noch einmal mit netz_protokoll.gd (Prüfmauer 2,
## eigene Drossel). Bringt die Sandbox etwas, das schon Prüfmauer 1 hätte abweisen müssen, oder
## einen kaputten Rahmen, glaubt Uzai ihr nichts mehr: Die Leitung ist zu (kaputt).
##
## Testbetrieb (windows_starten(rolle), „Abschottung prüfen“): Die Sandbox läuft mit „--test“; statt einer
## echten Gegenstelle schickt Uzai deren Bytes über die Leitung (TEST_REIN) und sieht, was hinausginge
## (TEST_RAUS). Die Gegenstelle mit guten und bösen Paketen steht in pruefen() – für „Abschottung prüfen“ und
## tests/logic_zimmer_netz.gd (dort gegen die Sandbox-Schleife in PowerShell 7 unter Linux). Im Testbetrieb
## öffnet nichts hier eine Verbindung ins Netz.
##
## Treffpunkt (Phase 3, src/room/treffpunkt.gd): Die Sandbox spricht mit Nostr-Relays, Ende-zu-Ende
## verschlüsselt; über die Leitung gehen nur Kennungen, Fingerabdrücke und Zustände – nie Adressen,
## nie Inhalte von Relays. Signiert wird mit libsecp256k1, verbunden mit libdatachannel (WebRTC-Datenkanal,
## Phase 4) – beide nur in der Sandbox (assets/net/, tools/bau_netzlibs.sh). Echte Relays und WebRTC gibt
## es nur im Echtbetrieb (windows_starten(rolle, true)). Den starten nur der Besuch (freundestest.gd, mit
## der letzten Schranke darf(): Zimmer online mit allen Bedingungen oder der Testschalter, beides nur nach
## bestandener Abschottung) und der Verbindungstest (Online.darf_testen).

const P := preload("res://src/room/netz_protokoll.gd")

## Rahmen-Arten (dieselben Nummern wie UzNetzRahmen im Helfer; der Test vergleicht).
const PING := 1
const PONG := 2
const ENDE := 5
const SENDEN := 6
const EMPFANGEN := 7
const TEST_REIN := 8
const TEST_RAUS := 9
const RAUS := 10
const ZAEHLER := 11
const SCHLIESSEN := 12
const TREFF := 13                   ## Uzai → Sandbox: Treffpunkt starten (u16 Port: 0 = feste Relays)
const EINLADUNG := 14               ## Uzai → Sandbox (Gastgeber): Kennung 16 + Schlüssel 32
const ZURUECK := 15                 ## Uzai → Sandbox (Gastgeber): Kennung 16
const BESUCH := 16                  ## Uzai → Sandbox (Gast): Kennung 16 + Schlüssel 32
const KLOPFT := 17                  ## Sandbox → Uzai (Gastgeber): Kennung 16 + Gast-Fingerabdruck 8
const ENTSCHEID := 18               ## Uzai → Sandbox (Gastgeber): Fingerabdruck 8 + Platz (0xFF = still abweisen)
const STAND := 19                   ## Sandbox → Uzai: Zustand, a, b
const TREFF_ZAEHLER := 20           ## beide: leer / sechs u32
const QUITTUNG := 21                ## nur Sandbox → Uzai: u32 – so viele Bytes hat sie insgesamt gelesen (mod 2^32)
const STAENDE := ["", "relays", "angenommen", "keine_antwort", "krypto_fehlt", "signatur_fehlt", "verbunden", "zu", "gescheitert", "direkt_fehlt"]
const MAX_RAHMEN := 8192            ## größte Nutzlast eines Rahmens
const PLAETZE := 8                  ## Gastgeber: ein Platz je Gast (Online.MAX_GAESTE_GRENZE)
const ROLLEN := ["gastgeber", "gast"]
const MAX_STUECK := 65536           ## so viel liest pumpen() auf einmal
## Ausgang zur Sandbox: Godot öffnet die Pipe ohne Warten. Unter Windows ist sie dann PIPE_NOWAIT mit 4 KiB
## Puffer (CreatePipe mit Größe 0); passt ein Schreibvorgang nicht ganz hinein, schreibt Windows nichts oder nur
## den Teil, den ein wartendes Lesen gerade nimmt, und store_buffer sagt nur „false“ – ein Rahmen ginge still
## verloren oder der Strom risse. Darum liegt nie mehr als FENSTER unquittiert in der Pipe (die Sandbox
## quittiert, was sie gelesen hat); dann passt jeder Schreibvorgang ganz hinein. Der Rest wartet in Uzai.
const FENSTER := 3072
const MAX_WARTEND := 262144         ## mehr wartet nie auf die Leitung – sonst geht sie zu (nie still verlieren)

## Die beiden Netz-Bibliotheken der Sandbox (tools/bau_netzlibs.sh). Dieselben Prüfsummen stehen im Helfer
## (UzNetzLib); tests/netzlibs_cs.ps1 vergleicht beide mit den Dateien. Uzai lädt sie nie selbst – es legt sie
## nur geprüft neben den Helfer (helper/net/), der sie geprüft neben die Sandbox legt, die sie geprüft lädt.
const NETZLIBS := {
	"uzai-secp256k1.dll": "24a4e9d05fbbf7158888ae1a69ee255b32fa855ce6c09c62a452b2c33ac7f072",
	"uzai-datachannel.dll": "7ee7217ad3848a65611838dda0bba4fdbe355635a8a3da5137992945d3206a8b",
}
const NETZLIBS_QUELLE := "res://assets/net/"
const NETZLIBS_ZIEL := "helper/net"
## Zustand je Bibliothek in „Abschottung prüfen“ (UzNetzLib): 1 bereit, 2 fehlt, 3 Prüfsumme, 4 Laden, 5 Selbsttest.
const NETZLIB_ZUSTAENDE := ["nicht versucht", "ja", "fehlt", "Prüfsumme falsch", "Laden gescheitert", "Selbsttest gescheitert"]


## Einen Rahmen bauen ([] bei unbekannter Art oder zu großer Nutzlast).
static func rahmen(art: int, nutz := PackedByteArray()) -> PackedByteArray:
	return Leitung.rahmen(art, nutz)


## Die Leitung ohne Prozess: Rahmen lesen, Prüfmauer 2, Ereignisse. Ohne Fenster testbar.
class Leitung:
	var rolle := "gastgeber"
	var test := true
	var kaputt := ""                ## Grund, sobald die Leitung zu ist ("" = in Ordnung)
	var verworfen := 0              ## Prüfmauer 2 hat abgelehnt (Bedeutung passte nicht)
	var gedrosselt := 0             ## Prüfmauer 2: Drossel
	var geschrieben := 0            ## so viele Bytes hat Uzai in die Pipe gelegt (Sitzung zählt)
	var quittiert := 0              ## davon hat die Sandbox so viele gelesen (QUITTUNG)
	var _puffer := PackedByteArray()
	var _drossel: Array = []
	var _raus: Array = []

	func _init(r: String, t := true) -> void:
		rolle = r if r in ROLLEN else "gast"
		test = t
		for i in plaetze():
			_drossel.append(P.Drossel.new())
			_raus.append(false)

	func plaetze() -> int:
		return PLAETZE if rolle == "gastgeber" else 1

	static func rahmen(art: int, nutz := PackedByteArray()) -> PackedByteArray:
		if art < PING or art > TREFF_ZAEHLER or nutz.size() > MAX_RAHMEN:
			return PackedByteArray()
		var b := PackedByteArray()
		b.resize(5)
		b.encode_u32(0, nutz.size() + 1)
		b[4] = art
		b.append_array(nutz)
		return b

	## Bytes aus der Leitung → Ereignisse:
	##   { art: "pong", nutz }, { art: "nachricht", platz, m: { a, d } }, { art: "raus", platz, von },
	##   { art: "test_raus", platz, b }, { art: "zaehler", angenommen, verworfen, gedrosselt, aus_verworfen, rein },
	##   { art: "klopft", kennung, gast }, { art: "stand", was, a, b },
	##   { art: "treff_zaehler", gesehen, unsinn, krypto, wiederholt, gedrosselt, relay }
	## QUITTUNG gibt kein Ereignis, sie rückt nur quittiert vor. Nach einem Fehler kommt nichts mehr (kaputt gesetzt).
	func eingang(b: PackedByteArray, jetzt: float) -> Array:
		var out: Array = []
		if kaputt != "":
			return out
		if b.size() > MAX_STUECK:
			_zu("stueck")
			return out
		_puffer.append_array(b)
		var p := 0        # so weit ist der Puffer gelesen
		while kaputt == "" and _puffer.size() - p >= 4:
			var n := _puffer.decode_u32(p)
			if n < 1 or n > MAX_RAHMEN + 1:
				_zu("laenge")
				break
			if _puffer.size() - p < 4 + n:
				break
			var art := _puffer[p + 4]
			var nutz := _puffer.slice(p + 5, p + 4 + n)
			p += 4 + n
			_rahmen(art, nutz, jetzt, out)
		# Das Gelesene in einem Zug abschneiden (früher nach jedem Rahmen: bei einem vollen Stück mit kleinen
		# Rahmen tausende Kopien des Rests). Nach einem Fehler ist der Puffer schon leer.
		if kaputt == "" and p > 0:
			_puffer = _puffer.slice(p)
		return out

	func _zu(grund: String) -> void:
		kaputt = grund
		_puffer.clear()

	func _rahmen(art: int, nutz: PackedByteArray, jetzt: float, out: Array) -> void:
		match art:
			PONG:
				out.append({ "art": "pong", "nutz": nutz })
			EMPFANGEN:
				if nutz.size() < 1 or nutz[0] >= plaetze():
					_zu("platz")
					return
				_nachricht(nutz[0], nutz.slice(1), jetzt, out)
			TEST_RAUS:
				# Was hinausginge, muss das Schema einhalten – sonst lügt die Sandbox.
				if not test or nutz.size() < 1 or nutz[0] >= plaetze() or not P.struktur_ok(nutz.slice(1), rolle == "gastgeber"):
					_zu("test_raus")
					return
				out.append({ "art": "test_raus", "platz": nutz[0], "b": nutz.slice(1) })
			RAUS:
				if nutz.size() != 2 or nutz[0] >= plaetze() or nutz[1] != 1:
					_zu("raus")
					return
				_raus[nutz[0]] = true
				out.append({ "art": "raus", "platz": nutz[0], "von": "sandbox" })
			ZAEHLER:
				# Fassung 5 der Sandbox hängt die Zahl der TEST_REIN-Rahmen an (20 Byte); ältere schicken 16 (rein -1).
				if nutz.size() != 16 and nutz.size() != 20:
					_zu("zaehler")
					return
				out.append({ "art": "zaehler", "angenommen": nutz.decode_u32(0), "verworfen": nutz.decode_u32(4),
						"gedrosselt": nutz.decode_u32(8), "aus_verworfen": nutz.decode_u32(12), "rein": nutz.decode_u32(16) if nutz.size() == 20 else -1 })
			QUITTUNG:
				# Zähler mod 2^32: der Abstand zum letzten Stand. Mehr quittieren, als Uzai geschrieben hat, geht nicht.
				if nutz.size() != 4:
					_zu("quittung")
					return
				var neu := quittiert + ((nutz.decode_u32(0) - (quittiert & 0xFFFFFFFF)) & 0xFFFFFFFF)
				if neu > geschrieben:
					_zu("quittung")
					return
				quittiert = neu
			KLOPFT:
				if rolle != "gastgeber" or nutz.size() != 24:
					_zu("klopft")
					return
				out.append({ "art": "klopft", "kennung": nutz.slice(0, 16), "gast": nutz.slice(16, 24).hex_encode() })
			STAND:
				if nutz.size() != 3 or nutz[0] < 1 or nutz[0] >= STAENDE.size() or ((nutz[0] == 6 or nutz[0] == 7 or nutz[0] == 8) and nutz[1] >= plaetze()):
					_zu("stand")
					return
				out.append({ "art": "stand", "was": STAENDE[nutz[0]], "a": nutz[1], "b": nutz[2] })
			TREFF_ZAEHLER:
				if nutz.size() != 24:
					_zu("treff_zaehler")
					return
				var z := { "art": "treff_zaehler" }
				var namen := ["gesehen", "unsinn", "krypto", "wiederholt", "gedrosselt", "relay"]
				for i in namen.size():
					z[namen[i]] = nutz.decode_u32(i * 4)
				out.append(z)
			_:
				_zu("art")

	## Prüfmauer 2 für eine Nachricht, die die Sandbox durchgelassen hat.
	func _nachricht(platz: int, m: PackedByteArray, jetzt: float, out: Array) -> void:
		var vom_gastgeber := rolle == "gast"
		if not P.struktur_ok(m, vom_gastgeber):
			_zu("mauer1")       # das hätte Prüfmauer 1 nie durchlassen dürfen
			return
		if _raus[platz]:
			verworfen += 1
			return
		var d: P.Drossel = _drossel[platz]
		var gelesen := P.lesen(m, vom_gastgeber)
		if gelesen.is_empty():
			verworfen += 1
			d.verstoss()
		elif not d.erlaubt(str(gelesen.a), m.size(), jetzt):
			gedrosselt += 1
			gelesen = {}
		if not gelesen.is_empty():
			out.append({ "art": "nachricht", "platz": platz, "m": gelesen })
		elif d.rauswerfen():
			_raus[platz] = true
			out.append({ "art": "raus", "platz": platz, "von": "uzai" })

	## Eine Nachricht an die Gegenstelle (über die Sandbox). [] wenn sie nicht ins Schema passt.
	func senden(platz: int, art: String, d: Dictionary = {}) -> PackedByteArray:
		var m := P.schreiben(art, d)
		if m.is_empty() or platz < 0 or platz >= plaetze() or (art == "zimmer" and rolle != "gastgeber"):
			return PackedByteArray()
		return rahmen(SENDEN, PackedByteArray([platz]) + m)

	## Nur im Testbetrieb: Bytes, als kämen sie von der Gegenstelle auf diesem Platz.
	func test_rein(platz: int, b: PackedByteArray) -> PackedByteArray:
		if not test or platz < 0 or platz >= plaetze() or b.size() >= MAX_RAHMEN:
			return PackedByteArray()
		return rahmen(TEST_REIN, PackedByteArray([platz]) + b)

	## Treffpunkt starten: port 0 = die festen Relays (gehen erst mit echter Nostr-Signatur), sonst
	## nur im Testbetrieb das Test-Relay auf 127.0.0.1:port.
	func treff(port := 0) -> PackedByteArray:
		if port < 0 or port > 65535 or (port != 0 and not test):
			return PackedByteArray()
		var n := PackedByteArray([0, 0])
		n.encode_u16(0, port)
		return rahmen(TREFF, n)

	## Gastgeber: dieses Postfach öffnen (Kennung und Schlüssel einer Einladung).
	func einladung(kennung: PackedByteArray, schluessel: PackedByteArray) -> PackedByteArray:
		if rolle != "gastgeber" or kennung.size() != 16 or schluessel.size() != 32:
			return PackedByteArray()
		return rahmen(EINLADUNG, kennung + schluessel)

	## Gastgeber: Postfach schließen (Einladung abgelaufen, benutzt oder zurückgezogen).
	func zurueck(kennung: PackedByteArray) -> PackedByteArray:
		if rolle != "gastgeber" or kennung.size() != 16:
			return PackedByteArray()
		return rahmen(ZURUECK, kennung)

	## Gast: mit dem Link anklopfen.
	func besuch(kennung: PackedByteArray, schluessel: PackedByteArray) -> PackedByteArray:
		if rolle != "gast" or kennung.size() != 16 or schluessel.size() != 32:
			return PackedByteArray()
		return rahmen(BESUCH, kennung + schluessel)

	## Gastgeber: Anklopfen annehmen (Platz) oder still abweisen (platz < 0).
	func entscheid(gast: String, platz: int) -> PackedByteArray:
		if rolle != "gastgeber" or gast.length() != 16 or platz >= plaetze():
			return PackedByteArray()
		for ch in gast:
			if not (ch in "0123456789abcdef"):
				return PackedByteArray()
		var g := gast.hex_decode()
		g.append(platz if platz >= 0 else 0xFF)
		return rahmen(ENTSCHEID, g)

	## Platz frei machen (Gast weg): Drossel und Rauswurf auf beiden Seiten zurück.
	func schliessen(platz: int) -> PackedByteArray:
		if platz < 0 or platz >= plaetze():
			return PackedByteArray()
		_drossel[platz] = P.Drossel.new()
		_raus[platz] = false
		return rahmen(SCHLIESSEN, PackedByteArray([platz]))


## Der Prozess dazu: Standardeingabe und -ausgabe sind die Leitung. Was Uzai schickt, wartet in einer
## Warteschlange, bis das Fenster (FENSTER) es erlaubt; geschrieben wird nur, was ganz in die Pipe passt.
class Sitzung:
	var io: FileAccess
	var err: FileAccess
	var pid := 0
	var leitung: Leitung
	var _aus: Array = []            ## wartende Rahmen (je schicken() ein Stück aus ganzen Rahmen)
	var _ab := 0                    ## so viel vom ersten ist schon geschrieben
	var _wartend := 0               ## Bytes in der Warteschlange

	func pumpen(jetzt: float) -> Array:
		var out := leitung.eingang(_lesen(), jetzt)
		_schieben()                 # die Quittungen eben haben das Fenster wieder geöffnet
		return out

	func schicken(b: PackedByteArray) -> void:
		if b.is_empty() or leitung.kaputt != "":
			return
		if _wartend + b.size() > MAX_WARTEND:
			_zu("voll")             # die Sandbox liest nicht mehr: lieber zu als still verlieren
			return
		_aus.append(b)
		_wartend += b.size()
		_schieben()

	## Bytes, die noch auf die Leitung warten.
	func wartend() -> int:
		return _wartend

	## Ins Fenster schreiben, was hineinpasst (auch nur ein Teil eines Rahmens – die Sandbox liest weiter,
	## bis er ganz ist). Scheitert ein Schreibvorgang trotzdem, ist unklar, wie viel ankam: Leitung zu.
	func _schieben() -> void:
		while _wartend > 0 and leitung.kaputt == "":
			var frei := FENSTER - (leitung.geschrieben - leitung.quittiert)
			if frei <= 0:
				return
			var stueck := PackedByteArray()
			while not _aus.is_empty() and stueck.size() < frei:
				var f: PackedByteArray = _aus[0]
				var n := mini(frei - stueck.size(), f.size() - _ab)
				stueck.append_array(f if _ab == 0 and n == f.size() else f.slice(_ab, _ab + n))
				_ab += n
				if _ab >= f.size():
					_aus.pop_front()
					_ab = 0
			_wartend -= stueck.size()
			if not _schreiben(stueck):
				_zu("schreiben")
				return
			leitung.geschrieben += stueck.size()

	func _zu(grund: String) -> void:
		leitung._zu(grund)
		_aus.clear()
		_ab = 0
		_wartend = 0
		abbrechen()

	## Die Pipe selbst (tests/logic_zimmer_leitung.gd ersetzt beide durch eine Attrappe).
	func _lesen() -> PackedByteArray:
		if io == null:
			return PackedByteArray()
		var b := io.get_buffer(MAX_STUECK)
		if err:
			err.get_buffer(MAX_STUECK)   # mitlesen, sonst blockiert ein voller Fehlerkanal; nie ins Log
		return b

	func _schreiben(b: PackedByteArray) -> bool:
		if io == null or not io.store_buffer(b):
			return false
		io.flush()
		return true

	func laeuft() -> bool:
		return pid > 0 and OS.is_process_running(pid)

	## Ende: Was noch wartet, braucht die Sandbox nicht mehr – nur der angefangene Rahmen wird fertig (sonst
	## risse der Strom), dann ENDE.
	func beenden() -> void:
		if _ab > 0:
			var f: PackedByteArray = _aus[0]
			_aus = [f]
			_wartend = f.size() - _ab
		else:
			_aus.clear()
			_wartend = 0
		schicken(Leitung.rahmen(ENDE))

	func abbrechen() -> void:
		if laeuft():
			OS.kill(pid)


## Startet einen Prozess als Sitzung (Programm und Argumente fest vom Aufrufer). null, wenn er
## nicht startet.
static func starten(programm: String, args: PackedStringArray, rolle: String) -> Sitzung:
	var info: Dictionary = OS.execute_with_pipe(programm, args, false)
	if info.is_empty():
		return null
	var s := Sitzung.new()
	s.io = info.get("stdio")
	s.err = info.get("stderr")
	s.pid = int(info.get("pid", 0))
	s.leitung = Leitung.new(rolle, true)
	return s


## Unter Windows: der Helfer mit „-ZimmerNetz <rolle>“ (er baut die Sandbox und startet sie im
## AppContainer). Nur feste Argumente; das Skript liegt in Uzais Datenordner (Helper._extract).
## echt: ohne Testbetrieb (feste Relays, WebRTC) – ob das sein darf, prüft der Aufrufer (freundestest.gd darf(),
## Verbindungstest: Online.darf_testen).
static func windows_starten(rolle: String, echt := false) -> Sitzung:
	if not (OS.get_name() == "Windows") or not (rolle in ROLLEN):
		return null
	var skript := Config.path("helper/uzai-helper.ps1")
	if not FileAccess.file_exists(skript):
		return null
	netzlibs_auslegen()
	var s := starten(Helper.ps_exe(), PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
			"-File", skript, "-ZimmerNetz", rolle + ("-echt" if echt else "")]), rolle)
	if s != null:
		s.leitung.test = not echt
	return s


## Die Netz-Bibliotheken neben den Helfer legen (nur mit der eingetragenen Prüfsumme; Ziel wird danach noch
## einmal geprüft). Rückgabe: Namen, die fehlen oder nicht stimmen (leer = alles da).
static func netzlibs_auslegen(ziel_ordner := "") -> Array:
	var dir := ziel_ordner if ziel_ordner != "" else Config.path(NETZLIBS_ZIEL)
	DirAccess.make_dir_recursive_absolute(dir)
	var fehlt: Array = []
	for name in NETZLIBS:
		var quelle: String = NETZLIBS_QUELLE + str(name)
		var ziel := dir.path_join(str(name))
		if FileAccess.get_sha256(ziel) == NETZLIBS[name]:
			continue
		var b := FileAccess.get_file_as_bytes(quelle)
		if b.is_empty() or FileAccess.get_sha256(quelle) != NETZLIBS[name]:
			fehlt.append(name)
			continue
		var f := FileAccess.open(ziel, FileAccess.WRITE)
		if f == null:
			fehlt.append(name)
			continue
		f.store_buffer(b)
		f.close()
		if FileAccess.get_sha256(ziel) != NETZLIBS[name]:
			DirAccess.remove_absolute(ziel)
			fehlt.append(name)
	return fehlt


# --- Test-Gegenstelle ------------------------------------------------------------------------------------

## Pakete der Test-Gegenstelle (Rolle Gastgeber, Gäste auf Platz 1): [Bytes, soll Prüfmauer 1
## passieren, soll Prüfmauer 2 passieren, was].
static func faelle() -> Array:
	var gut: Array = [
		[P.schreiben("hallo", { "geraet": "web" }), "hallo"],
		[P.schreiben("pos", { "x": 320, "y": 0, "z": 450, "yaw": -1200, "pitch": 300 }), "pos"],
		[P.schreiben("emote", { "id": "winken" }), "emote"],
		[P.schreiben("satz", { "id": "gg" }), "satz"],
		[P.schreiben("figur", { "figur": { "person": "ben" }, "tier": { "art": "fuchs" } }), "figur"],
		[P.schreiben("tschuess"), "tschuess"],
	]
	var out: Array = []
	for g in gut:
		out.append([g[0], true, true, g[1]])
	var pos: PackedByteArray = gut[1][0]
	var hallo: PackedByteArray = (gut[0][0] as PackedByteArray).duplicate()
	hallo.encode_u32(4, P.stempel() ^ 0x5A5A5A5A)
	out.append([hallo, true, false, "hallo mit fremdem Schema-Stempel (nur Prüfmauer 2 kennt ihn)"])
	var weit := pos.duplicate()
	weit.encode_u16(3, P.X_MAX + 1)
	var lang := pos.duplicate()
	lang.append(0)
	var alt := pos.duplicate()
	alt[1] = 1
	var emote := (gut[2][0] as PackedByteArray).duplicate()
	emote[3] = P.EMOTES.size()
	var figur := (gut[4][0] as PackedByteArray).duplicate()
	figur[3] = 200
	var boese: Array = [
		[P.schreiben("zimmer", { "raum": P.Daten.standard_raum() }), "Zimmer von einem Gast"],
		["1b0000000200000004000000010000006100000004000000040000007361747a".hex_decode(), "Godot-Variant-Bytes"],
		["Object(Script,\"script/source\":\"extends Node\")".to_utf8_buffer(), "Godot-Text mit Skript"],
		["{\"v\":1,\"a\":\"chat\",\"d\":{\"text\":\"hi\"}}".to_utf8_buffer(), "alter Text-Chat"],
		[pos.slice(0, 12), "abgeschnitten"], [lang, "ein Byte zu viel"], [weit, "außerhalb des Zimmers"],
		[alt, "alte Fassung"], [emote, "unbekanntes Emote"], [figur, "unbekannte Figur-Option"],
		[PackedByteArray([P.MAGIC, P.VERSION, 9]), "unbekannte Art"], [PackedByteArray(), "leer"],
	]
	var gross := PackedByteArray()
	gross.resize(5000)
	gross.fill(P.MAGIC)
	boese.append([gross, "5000 Byte"])
	for e in boese:
		out.append([e[0], false, false, e[1]])
	return out


## Die Test-Gegenstelle gegen eine laufende Sitzung (Rolle Gastgeber): Echo, gute und böse Pakete,
## Flut (Drossel), Dauer-Unsinn (Rauswurf), Ausgehendes nur nach Schema, sauberes Ende.
## { ok, leitung, rahmen, mauer1, mauer2, drossel, rauswurf, ausgang, ende, fehler }. rahmen: Die Sandbox hat jeden
## TEST_REIN-Rahmen bekommen (ihr Zähler) – sonst liegt ein Fehler an der Leitung, nicht an einer Prüfmauer.
## fehler beginnt mit „leitung “ (Leitung) oder „pruefung “ (Prüfmauer), sonst „start“, „keine Antwort“, „keine Zähler“.
static func pruefen(s: Sitzung, tree: SceneTree, zeit_s := 60.0) -> Dictionary:
	var r := { "ok": false, "leitung": false, "rahmen": false, "mauer1": false, "mauer2": false, "drossel": false, "rauswurf": false, "ausgang": false,
			"ende": false, "fehler": "" }
	if s == null:
		r.fehler = "start"
		return r
	var t0 := Time.get_ticks_msec()
	var ereignisse: Array = []
	var warte := func(bis: Callable) -> bool:
		while Time.get_ticks_msec() - t0 < int(zeit_s * 1000.0):
			ereignisse.append_array(s.pumpen(Time.get_ticks_msec() / 1000.0))
			if s.leitung.kaputt != "" or bis.call():
				return s.leitung.kaputt == ""
			if not s.laeuft():
				ereignisse.append_array(s.pumpen(Time.get_ticks_msec() / 1000.0))
				return s.leitung.kaputt == "" and bis.call()
			await tree.process_frame
		return false
	# 1. Echo: die Leitung steht (beim ersten Mal baut der Helfer die Sandbox, das dauert).
	var zufall := Crypto.new().generate_random_bytes(300)
	s.schicken(rahmen(PING, zufall))
	var pong := func() -> bool:
		for e in ereignisse:
			if e.art == "pong":
				return true
		return false
	if not await warte.call(pong):
		r.fehler = "keine Antwort" if s.leitung.kaputt == "" else _kaputt_grund(s.leitung.kaputt)
		s.abbrechen()
		return r
	for e in ereignisse:
		if e.art == "pong":
			r.leitung = e.nutz == zufall
	ereignisse.clear()
	# 2. Gute und böse Pakete auf Platz 1, Flut auf Platz 2, Dauer-Unsinn auf Platz 3, Ausgehendes.
	var l := s.leitung
	var fl := faelle()
	var rein := fl.size() + 60 + 40     # so viele TEST_REIN-Rahmen gehen hinaus
	for f in fl:
		s.schicken(l.test_rein(1, f[0]))
	# Die Flut in einem Stück (ein Schreibvorgang, soweit das Fenster reicht).
	var flut_paket := PackedByteArray()
	for i in 60:
		flut_paket.append_array(l.test_rein(2, P.schreiben("pos", { "x": 100 + i, "y": 0, "z": 100, "yaw": 0, "pitch": 0 })))
	s.schicken(flut_paket)
	for i in 40:
		s.schicken(l.test_rein(3, PackedByteArray([P.MAGIC, P.VERSION, 2, i])))
	s.schicken(l.senden(1, "pos", { "x": 10, "y": 0, "z": 10, "yaw": 0, "pitch": 0 }))
	s.schicken(l.senden(1, "zimmer", { "raum": P.Daten.standard_raum() }))
	s.schicken(rahmen(SENDEN, PackedByteArray([1]) + "{\"a\":\"chat\"}".to_utf8_buffer()))
	s.schicken(rahmen(ZAEHLER))
	var zaehler := {}
	var hat_zaehler := func() -> bool:
		for e in ereignisse:
			if e.art == "zaehler":
				zaehler.merge(e)
				return true
		return false
	if not await warte.call(hat_zaehler):
		r.fehler = "keine Zähler" if s.leitung.kaputt == "" else _kaputt_grund(s.leitung.kaputt)
		s.abbrechen()
		return r
	var durch2: Array = []
	var flut := 0
	var raus3 := false
	var raus_ausgang: Array = []
	for e in ereignisse:
		match str(e.art):
			"nachricht":
				if int(e.platz) == 1:
					durch2.append(e.m)
				elif int(e.platz) == 2:
					flut += 1
			"raus":
				raus3 = raus3 or (int(e.platz) == 3 and e.von == "sandbox")
			"test_raus":
				raus_ausgang.append(P.ARTEN[(e.b as PackedByteArray)[2]])
	var soll1 := 0
	var soll2: Array = []
	for f in fl:
		if f[1]:
			soll1 += 1
		if f[2]:
			soll2.append(f[3])
	var gelesen2: Array = []
	for m in durch2:
		gelesen2.append(str(m.a))
	# Prüfmauer 1: genau die gültigen kamen durch (auf Platz 2 die Flut bis zur Drossel), der Rest
	# wurde verworfen. Prüfmauer 2: liest dieselben, lehnt den fremden Stempel ab, drosselt selbst.
	var flut1 := int(zaehler.angenommen) - soll1
	r.rahmen = int(zaehler.rein) == rein
	r.mauer1 = int(zaehler.verworfen) == (fl.size() - soll1) + 40 and flut1 >= 40 and flut1 < 60
	r.mauer2 = gelesen2 == soll2 and l.verworfen == soll1 - soll2.size() and flut + l.gedrosselt == flut1
	r.drossel = int(zaehler.gedrosselt) == 60 - flut1
	r.rauswurf = raus3
	r.ausgang = raus_ausgang == ["pos", "zimmer"] and int(zaehler.aus_verworfen) == 1
	# 3. Ende: die Sandbox beendet sich.
	s.beenden()
	var weg := func() -> bool: return not s.laeuft()
	r.ende = await warte.call(weg)
	if not r.ende:
		s.abbrechen()
	r.ok = r.leitung and r.rahmen and r.mauer1 and r.mauer2 and r.drossel and r.rauswurf and r.ausgang and r.ende
	if not r.ok and r.fehler == "":
		# Erst die Leitung (kaputt, Rahmen verloren), dann die Mauern mit ihren Zählern: verworfen (Soll),
		# angenommene Flut, gedrosselt.
		if s.leitung.kaputt != "":
			r.fehler = _kaputt_grund(s.leitung.kaputt)
		elif not r.rahmen:
			r.fehler = "leitung %d/%d rahmen" % [int(zaehler.rein), rein]
		else:
			r.fehler = "pruefung v%d/%d f%d g%d" % [int(zaehler.get("verworfen", -1)), (fl.size() - soll1) + 40, flut1, int(zaehler.get("gedrosselt", -1))]
	return r


## Grund, wenn Uzai die Leitung zugemacht hat: „mauer1“/„test_raus“ heißt, die Sandbox ließ etwas durch, das
## Prüfmauer 1 abweisen musste (Prüfmauer); alles andere (Länge, Art, Quittung, schreiben, voll …) ist die Leitung.
static func _kaputt_grund(k: String) -> String:
	return ("pruefung " if k in ["mauer1", "test_raus"] else "leitung ") + k

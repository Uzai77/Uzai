extends RefCounted
## Zimmer teilen (Punkt 131, Stufe 3) – ohne Upload, ohne Server, ohne Telemetrie (R6/R8). Reine
## Logik, ohne Fenster testbar (tests/logic_zteilen.gd); die Bedienung steht in teilen_ui.gd,
## einfuehren_ui.gd und zimmer.gd.
##
## Was mitreist (auszug): ein Raum (Wände, Boden, Licht, Möbel samt Gestaltung), die eigenen Möbel
## aus dem Baukasten, die darin stehen, Figur und Haustier (Aussehen, ohne den Namen). Was nie
## mitreist: Spiele und Bibliothek (eigene Reihenfolge im Regal, Auswahl nach Ordnern, Listen, Tags,
## Sammlungen), Namen (Zimmer, eigene Stimmungen), Spielstand und Meilensteine, eigene Farben.
##
## Als Datei: „.uzaizimmer“ = ZIP mit zimmer.json (Schema von zimmer_daten.gd, Fassung 2, ein Raum)
## und vorschau.jpg. Als Code (QR, Zwischenablage): „UZZ1:“ + Base64 eines ZIP nur mit zimmer.json,
## wenn er klein genug ist.
##
## Einführen: Fremde Pakete gelten als feindlich. Erst der strenge ZIP-Leser (src/core/paket.gd:
## keine Verknüpfungen, kein Zip-Slip – nur genau zwei feste Namen –, keine Bomben, Größen- und
## Anzahlgrenzen, Prüfsummen), dann derselbe Prüfer wie für zimmer.json (zimmer_daten.gd pruefe):
## nur Kennungen aus dem Katalog, Farben „#rrggbb“, Zahlen in festen Bereichen. Das Vorschaubild
## wird nur im Kopf geprüft (Format, Größe) und nie dekodiert – die Vorschau beim Einführen rechnet
## Uzai selbst aus den geprüften Daten. Nichts wird ausgeführt oder als Ressource geladen.
##
## Geschrieben wird atomar (erst „.neu“, wieder eingelesen und verglichen, dann umbenannt) und nur
## in Uzais eigene Ordner (Dokumente\Uzai\Zimmer, Bilder\Uzai), nie über Verknüpfungen.

const Daten := preload("res://src/room/zimmer_daten.gd")
const Katalog := preload("res://src/room/katalog.gd")
const G := preload("res://src/room/gestalt.gd")
const FD := preload("res://src/room/figur/figur_daten.gd")
const M := preload("res://src/room/figur/meilensteine.gd")
const Paket := preload("res://src/core/paket.gd")
const MediaDaten := preload("res://src/core/media_daten.gd")
const Zip := preload("res://src/core/zip_pruefung.gd")
const L := preload("res://src/core/capture_logic.gd")
const Fremd := preload("res://src/core/fremd.gd")

const ENDUNG := "uzaizimmer"
const CODE_PREFIX := "UZZ1:"
const QR_MAX := 2200                 ## so viel fasst ein gut lesbarer QR-Code
const MAX_DATEI := 2 * 1024 * 1024
const MAX_JSON := 256 * 1024
const MAX_VORSCHAU := 768 * 1024
const VORSCHAU_PX := 1920            ## Vorschaubild höchstens so breit bzw. hoch
const VORSCHAU_GROESSE := Vector2i(1280, 720)
const JSON_NAME := "zimmer.json"
const BILD_NAME := "vorschau.jpg"
const DATEI_RE := "^zimmer-[0-9]{8}-[0-9]{6}(-[0-9]{1,3})?\\.uzaizimmer$"
const RAUM_ID := "geteilt"
const RAUM_NAME := "Geteiltes Zimmer"
## Auswahl der Spiele im Regal, die nichts über die Bibliothek verrät („eigene“ reist ohne die Spiele:
## beim Empfänger steht das Regal leer, bis er selbst einräumt).
const FILTER_OHNE_BIBLIOTHEK := ["eigene", "alle", "installiert", "favoriten", "ungespielt"]


# --- Auszug: was mitreist ------------------------------------------------------------------------

## Der Ausschnitt zum Teilen aus dem Zimmer (zimmer_daten.gd) und dem Raum, der geteilt wird –
## geprüft wie zimmer.json. {} wenn daraus kein gültiges Zimmer wird.
static func auszug(daten: Dictionary, raum: Dictionary) -> Dictionary:
	var r: Dictionary = raum.duplicate(true)
	r["id"] = RAUM_ID
	r["name"] = RAUM_NAME
	# Eigene Stimmung: ihr Name bleibt hier, das Licht selbst reist mit.
	if r.get("licht") is Dictionary:
		var st := str(r.licht.get("st", ""))
		if st != "" and G.stimmung(st).is_empty():
			r.licht.st = ""
	var benutzt := {}
	var moebel: Array = []
	for m in r.get("moebel", []):
		if not (m is Dictionary):
			continue
		var it: Dictionary = m
		_ohne_bibliothek(it)
		benutzt[str(it.get("t", ""))] = true
		moebel.append(it)
	r["moebel"] = moebel
	var eigene: Array = []
	for e in daten.get("eigene", []):
		if e is Dictionary and benutzt.has(str(e.get("id", ""))):
			eigene.append((e as Dictionary).duplicate(true))
	var tier := FD.pruefe_tier(daten.get("tier"))
	tier["name"] = FD.TIER_NAME
	var roh := { "format": Daten.FORMAT, "version": Daten.VERSION, "aktuell": RAUM_ID, "raeume": [r], "eigene": eigene,
		"figur": FD.pruefe_figur(daten.get("figur")), "tier": tier, "regale": Daten.REGALE_EIGEN }
	var sauber := pruefen(roh)
	if sauber.is_empty():
		return {}
	return _knapp(sauber)


## Regal-Einstellungen ohne Bibliothek: keine eigene Reihenfolge (Spiel-IDs), keine Auswahl nach
## Ordnern, Listen, Tags, Sammlungen, Status oder Genre (Namen des Nutzers).
static func _ohne_bibliothek(it: Dictionary) -> void:
	if not (it.get("rg") is Dictionary):
		return
	var rg: Dictionary = (it.rg as Dictionary).duplicate(true)
	for k in ["ma", "pl", "lg"]:     # Spiel-IDs bleiben zu Hause (auch die von Hand gestellten)
		rg.erase(k)
	if str(rg.get("so", "")) == "manuell":
		rg.so = "zuletzt"
	if rg.has("fi"):
		var fi := str(rg.fi)
		if not (fi in FILTER_OHNE_BIBLIOTHEK or fi.begins_with("system:") or fi.begins_with("systeme:")):
			rg.fi = G.FILTER_STD
	it["rg"] = rg


## Nur, was zum Zimmer gehört (keine leeren Listen des Nutzers), und Möbel ohne Standardwerte: hält
## Datei und Code klein. Der Prüfer setzt die Standardwerte beim Einlesen wieder.
static func _knapp(d: Dictionary) -> Dictionary:
	var raum: Dictionary = (d.raeume[0] as Dictionary).duplicate(true)
	var moebel: Array = []
	for m in raum.moebel:
		var it: Dictionary = (m as Dictionary).duplicate(true)
		if int(it.get("r", 0)) == 0:
			it.erase("r")
		if bool(it.get("an", true)):
			it.erase("an")
		if str(it.get("v", "")) == Katalog.std_variante(str(it.t)):
			it.erase("v")
		moebel.append(it)
	raum.moebel = moebel
	return { "format": d.format, "version": d.version, "aktuell": RAUM_ID, "raeume": [raum], "eigene": d.eigene,
		"figur": d.figur, "tier": d.tier, "regale": Daten.REGALE_EIGEN }


## Derselbe Prüfer wie für zimmer.json. Er meldet dabei die eigenen Möbel des Pakets beim Katalog
## an (die Räume dürfen sie benutzen) – danach gilt wieder, was vorher angemeldet war.
static func pruefen(roh: Variant) -> Dictionary:
	var vorher := Katalog.eigene_liste()
	var s := Daten.pruefe(roh)
	Katalog.eigene_setzen(vorher)
	return s


static func json(auszug_: Dictionary) -> PackedByteArray:
	return JSON.stringify(auszug_).to_utf8_buffer()


# --- Datei und Code ---------------------------------------------------------------------------------

## Das Paket (.uzaizimmer): zimmer.json und, wenn es eins gibt, das Vorschaubild (JPEG).
static func paket(auszug_: Dictionary, vorschau: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var entries: Array = [[JSON_NAME, json(auszug_)]]
	if not vorschau.is_empty():
		entries.append([BILD_NAME, vorschau])
	return Paket.zip(entries)


## Vorschaubild für das Paket: höchstens VORSCHAU_GROESSE, als JPEG.
static func vorschau_jpg(img: Image) -> PackedByteArray:
	if img == null or img.is_empty():
		return PackedByteArray()
	var i: Image = img.duplicate()
	if i.get_format() != Image.FORMAT_RGB8:
		i.convert(Image.FORMAT_RGB8)
	var f := minf(1.0, minf(float(VORSCHAU_GROESSE.x) / i.get_width(), float(VORSCHAU_GROESSE.y) / i.get_height()))
	if f < 1.0:
		i.resize(maxi(1, roundi(i.get_width() * f)), maxi(1, roundi(i.get_height() * f)), Image.INTERPOLATE_LANCZOS)
	return i.save_jpg_to_buffer(0.86)


## Zimmer-Code für QR und Zwischenablage; "" wenn er zu lang für einen lesbaren QR-Code wäre.
static func code(auszug_: Dictionary) -> String:
	var t := CODE_PREFIX + Marshalls.raw_to_base64(Paket.zip([[JSON_NAME, json(auszug_)]]))
	return t if t.length() <= QR_MAX else ""


# --- Einlesen (fremde Daten) -------------------------------------------------------------------------

static func _fehler(text: String) -> Dictionary:
	return { "ok": false, "error": text }


## Eine .uzaizimmer-Datei lesen und vollständig prüfen. Ergebnis wie lesen_bytes.
static func lesen_datei(pfad: String) -> Dictionary:
	if pfad.get_extension().to_lower() != ENDUNG:
		return _fehler("Das ist keine Zimmer-Datei (.uzaizimmer).")
	if Paket.is_link(pfad):
		return _fehler("Die Datei ist eine Verknüpfung – Uzai liest sie nicht.")
	var f := FileAccess.open(pfad, FileAccess.READ)
	if f == null:
		return _fehler("Die Datei lässt sich nicht öffnen.")
	var n := f.get_length()
	if n <= 0 or n > MAX_DATEI:
		f.close()
		return _fehler("Die Datei ist zu groß für ein Zimmer." if n > 0 else "Die Datei ist leer.")
	var b := f.get_buffer(n)
	f.close()
	return lesen_bytes(b)


## Paket (ZIP) → geprüftes Zimmer. Ergebnis: { ok, error, daten (wie zimmer.json, ein Raum),
## raum, eigene (die darin benutzt werden), figur, tier, vorschau (Bytes, nur im Kopf geprüft) }.
static func lesen_bytes(b: PackedByteArray) -> Dictionary:
	if b.size() > MAX_DATEI:
		return _fehler("Die Datei ist zu groß für ein Zimmer.")
	var idx := Paket.verzeichnis(b, JSON_NAME, { BILD_NAME: MAX_VORSCHAU })
	if not bool(idx.ok):
		# Dem Nutzer reicht ein klarer Satz; der genaue Grund steht dabei (für Tests und Protokoll).
		var f := _fehler("Das ist kein gültiges Uzai-Zimmer.")
		f["grund"] = str(idx.error)
		return f
	var dateien := {}
	for e in idx.entries:
		# Gepackte Einträge prüft der Entpacker, ungepackte prüft Zip.entpacken gegen ihre Prüfsumme.
		var data: Variant = Zip.entpacken(b, e)
		if data == null:
			return _fehler("Das Zimmer-Paket ist beschädigt.")
		dateien[str(e.name)] = data
	var vorschau := PackedByteArray()
	if dateien.has(BILD_NAME):
		vorschau = dateien[BILD_NAME]
		var gr := MediaDaten.kopf_groesse(vorschau, "jpg")
		if gr.x <= 0 or gr.y <= 0 or gr.x > VORSCHAU_PX or gr.y > VORSCHAU_PX:
			return _fehler("Das Vorschaubild im Paket ist ungültig.")
	var jb: PackedByteArray = dateien[JSON_NAME]
	var txt := jb.get_string_from_utf8()
	if txt == "" or txt.length() > MAX_JSON:
		return _fehler("Das Zimmer-Paket ist beschädigt.")
	var roh: Variant = Fremd.json_roh(txt)
	if not (roh is Dictionary):
		return _fehler("Das ist kein gültiges Uzai-Zimmer.")
	var sauber := pruefen(roh)
	if sauber.is_empty():
		return _fehler("Das ist kein gültiges Uzai-Zimmer.")
	var raum: Dictionary = sauber.raeume[0]
	for r in sauber.raeume:
		if str(r.id) == str(sauber.aktuell):
			raum = r
	# Fremde Namen übernimmt Uzai nicht: Der Raum heißt immer „Geteiltes Zimmer“.
	raum.id = RAUM_ID
	raum.name = RAUM_NAME
	var benutzt := {}
	for m in raum.moebel:
		benutzt[str(m.t)] = true
	var eigene: Array = (sauber.eigene as Array).filter(func(e: Dictionary) -> bool: return benutzt.has(str(e.id)))
	var tier: Dictionary = sauber.tier
	tier["name"] = FD.TIER_NAME
	# Der Prüfer hat alte Regale schon leer geräumt: der Vermerk reist mit (sonst noch einmal).
	var daten := { "format": Daten.FORMAT, "version": Daten.VERSION, "aktuell": str(raum.id), "raeume": [raum], "eigene": eigene,
		"figur": sauber.figur, "tier": tier, "regale": Daten.REGALE_EIGEN }
	return { "ok": true, "error": "", "daten": daten, "raum": raum, "eigene": eigene, "figur": sauber.figur, "tier": tier, "vorschau": vorschau }


## Zimmer-Code (aus der Zwischenablage oder getippt): Länge und Zeichen prüfen, Base64 zu Bytes,
## dann derselbe Weg wie eine Datei.
static func code_lesen(text: String) -> Dictionary:
	if text.length() > QR_MAX * 3:
		return _fehler("Der Zimmer-Code ist zu lang.")
	var t := text.strip_edges().replace("\n", "").replace("\r", "").replace(" ", "")
	if not t.begins_with(CODE_PREFIX):
		return _fehler("Das ist kein Zimmer-Code (er beginnt mit „UZZ1:“).")
	t = t.substr(CODE_PREFIX.length())
	if t.length() < 16 or t.length() > QR_MAX * 2 or t.length() % 4 != 0 or not RegEx.create_from_string("^[A-Za-z0-9+/]+={0,2}$").search(t):
		return _fehler("Der Zimmer-Code ist unvollständig oder beschädigt.")
	var b := Marshalls.base64_to_raw(t)
	if b.is_empty():
		return _fehler("Der Zimmer-Code ist beschädigt.")
	return lesen_bytes(b)


# --- Übernehmen ---------------------------------------------------------------------------------------

## Ein gelesenes Zimmer für dieses Zimmer vorbereiten: eigene Möbel des Pakets bekommen neue
## Kennungen (gleiche Möbel, die es hier schon gibt, werden wiederverwendet), gesperrte Möbel
## (Meilensteine, nur durchs Spielen) bleiben weg, und der Raum geht noch einmal durch den Prüfer –
## mit allen eigenen Möbeln zusammen. Ergebnis: { raum, eigene (die ganze neue Liste), neu,
## weg_eigene, weg_gesperrt, moebel }.
static func vorbereiten(gelesen: Dictionary, eigene_jetzt: Array, erreichte: Array) -> Dictionary:
	var liste: Array = eigene_jetzt.duplicate(true)
	var ids := {}
	for e in liste:
		ids[str(e.id)] = true
	var karte := {}
	var neu := 0
	var weg_eigene := 0
	for e in gelesen.get("eigene", []):
		var fremd: Dictionary = e
		var gleich := ""
		for own in liste:
			if _gleiches_moebel(own, fremd):
				gleich = str(own.id)
				break
		if gleich != "":
			karte[str(fremd.id)] = gleich
			continue
		if liste.size() >= G.MAX_EIGENE:
			karte[str(fremd.id)] = ""
			weg_eigene += 1
			continue
		var kopie: Dictionary = fremd.duplicate(true)
		kopie.id = neue_kennung(G.EIGEN_PRAEFIX, ids)
		ids[kopie.id] = true
		liste.append(kopie)
		karte[str(fremd.id)] = str(kopie.id)
		neu += 1
	var raum: Dictionary = (gelesen.get("raum", {}) as Dictionary).duplicate(true)
	var moebel: Array = []
	var weg_gesperrt := 0
	for m in raum.get("moebel", []):
		var it: Dictionary = m
		var t := str(it.t)
		if karte.has(t):
			if str(karte[t]) == "":
				continue
			it.t = karte[t]
		elif not M.ist_frei("moebel:" + t, erreichte):
			weg_gesperrt += 1
			continue
		moebel.append(it)
	raum.moebel = moebel
	var vorher := Katalog.eigene_liste()
	Katalog.eigene_setzen(liste)
	var sauber := Daten.pruefe_raum(raum)
	Katalog.eigene_setzen(vorher)
	return { "raum": sauber, "eigene": liste, "neu": neu, "weg_eigene": weg_eigene, "weg_gesperrt": weg_gesperrt,
		"moebel": (sauber.get("moebel", []) as Array).size() }


static func _gleiches_moebel(a: Dictionary, b: Dictionary) -> bool:
	for k in ["name", "ebene", "w", "d", "teile"]:
		if JSON.stringify(a.get(k)) != JSON.stringify(b.get(k)):
			return false
	return true


static func neue_kennung(praefix: String, vorhanden: Dictionary) -> String:
	var zeichen := "abcdefghijklmnopqrstuvwxyz0123456789"
	for _v in 400:
		var id := praefix
		for _i in 6:
			id += zeichen[randi() % zeichen.length()]
		if not vorhanden.has(id):
			return id
	return praefix + str(Time.get_ticks_usec() % 100000000)


## Eine eigene Vorlage aus einem vorbereiteten Raum (zimmer_daten.gd pruefe_vorlage).
static func vorlage(raum: Dictionary, name: String, vorhanden: Array) -> Dictionary:
	var ids := {}
	for v in vorhanden:
		ids[str(v.get("id", ""))] = true
	return Daten.pruefe_vorlage({ "id": neue_kennung(Daten.VORLAGE_PRAEFIX, ids), "name": name, "raum": raum })


# --- Schreiben ----------------------------------------------------------------------------------------

## Ordner für geteilte Zimmer: Dokumente\Uzai\Zimmer. [Basis, Ordner] – geschrieben wird nur ab der
## Basis Dokumente\Uzai (Uzais eigener Ordner); in Tests im Datenordner.
static func export_ordner() -> Array:
	var basis := Paket.export_basis()
	return [basis, basis.path_join("Zimmer")]


## Ordner für Schnappschüsse: Bilder\Uzai wie Bildschirmfotos (capture.gd) – in Tests im Datenordner.
static func foto_ordner() -> Array:
	var pics := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if OS.get_environment("UZAI_DATA") != "" or pics == "":
		var d := Config.path("export").path_join("Bilder")
		return [Config.path("export"), d]
	var base := pics.path_join("Uzai")
	return [base, base]


## Dateiname nach fester Regel: zimmer-JJJJMMTT-hhmmss.uzaizimmer (bei Gleichstand „-2“ …).
static func dateiname(ordner: String, wann: Dictionary) -> String:
	var basis := "zimmer-%04d%02d%02d-%02d%02d%02d" % [int(wann.year), int(wann.month), int(wann.day), int(wann.hour), int(wann.minute), int(wann.second)]
	var name := basis + "." + ENDUNG
	var n := 2
	while FileAccess.file_exists(ordner.path_join(name)) and n < 1000:
		name = "%s-%d.%s" % [basis, n, ENDUNG]
		n += 1
	return name


## Paket atomar schreiben: erst „.neu“, mit dem strengen Leser wieder einlesen und mit dem Auszug
## vergleichen, dann umbenannt. Nie über eine Verknüpfung. Ergebnis: { ok, error, pfad }.
static func schreiben(basis: String, ordner: String, datei: String, bytes: PackedByteArray, auszug_: Dictionary) -> Dictionary:
	if not RegEx.create_from_string(DATEI_RE).search(datei):
		return { "ok": false, "error": "Ungültiger Dateiname." }
	var why := Paket.safe_dir(basis, ordner)
	if why != "":
		return { "ok": false, "error": why }
	var ziel := ordner.path_join(datei)
	var tmp := ziel + ".neu"
	for p in [ziel, tmp]:
		if Paket.is_link(p):
			return { "ok": false, "error": "Am Ziel liegt eine Verknüpfung – Uzai schreibt dort nicht." }
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	var w := FileAccess.open(tmp, FileAccess.WRITE)
	if w == null:
		return { "ok": false, "error": "Uzai kann dort nicht schreiben." }
	w.store_buffer(bytes)
	w.close()
	var zurueck := lesen_bytes(FileAccess.get_file_as_bytes(tmp))
	if not bool(zurueck.ok) or not gleich(zurueck.daten, auszug_):
		DirAccess.remove_absolute(tmp)
		return { "ok": false, "error": "Die Prüfung der neuen Datei ist fehlgeschlagen." }
	if FileAccess.file_exists(ziel):
		DirAccess.remove_absolute(ziel)
	if DirAccess.rename_absolute(tmp, ziel) != OK:
		DirAccess.remove_absolute(tmp)
		return { "ok": false, "error": "Uzai kann dort nicht schreiben." }
	return { "ok": true, "error": "", "pfad": ziel }


## Zwei Zimmer gleich (nach dem Prüfer, mit Standardwerten)?
static func gleich(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(pruefen(a)) == JSON.stringify(pruefen(b))


## Schnappschuss als PNG unter Bilder\Uzai („Dein Zimmer 2026-10-23 20-15-04.png“, wie
## Bildschirmfotos benannt, damit „Aufnahmen“ ihn zeigt). Atomar über „.neu“. Pfad oder "".
## Zwei Schritte, weil das PNG Zeit kostet (gemessen 0,8 s bei 1080p, 3,3 s bei 4K): foto_ziel im Hauptfaden,
## foto_schreiben im Hilfsfaden. foto_speichern macht beides hintereinander.
static func foto_speichern(img: Image, ordner_: Array = []) -> String:
	if img == null or img.is_empty():
		return ""
	return foto_schreiben(img, foto_ziel(ordner_))


## Wohin der nächste Schnappschuss kommt ("" = dort geht es nicht). belegt: Namen, die gerade geschrieben werden.
static func foto_ziel(ordner_: Array = [], belegt: Array = []) -> String:
	var o: Array = ordner_ if ordner_.size() == 2 else foto_ordner()
	if Paket.safe_dir(str(o[0]), str(o[1])) != "":
		return ""
	var dir := str(o[1])
	var da: Array = Array(DirAccess.get_files_at(dir))
	da.append_array(belegt)
	return dir.path_join(L.unique_name(da, L.capture_name(TranslationServer.translate("Dein Zimmer"), Time.get_datetime_dict_from_system(), "png")))


## Reine Dateiarbeit (läuft auch im Hilfsfaden): das Bild als PNG nach ziel. Pfad oder "".
static func foto_schreiben(img: Image, ziel: String) -> String:
	if img == null or img.is_empty() or ziel == "":
		return ""
	var tmp := ziel + ".neu"
	for p in [ziel, tmp]:
		if Paket.is_link(p):
			return ""
	if img.save_png(tmp) != OK:
		DirAccess.remove_absolute(tmp)
		return ""
	if DirAccess.rename_absolute(tmp, ziel) != OK:
		DirAccess.remove_absolute(tmp)
		return ""
	return ziel


## Dezentes Uzai-Zeichen unten rechts ins Bild (marke: helle Schrift auf durchsichtigem Grund,
## vorher einmal gezeichnet). Die Deckkraft ist bewusst gering.
static func wasserzeichen(img: Image, marke: Image, deckkraft := 0.55) -> void:
	if img == null or marke == null or marke.is_empty():
		return
	var m: Image = marke.duplicate()
	m.convert(Image.FORMAT_RGBA8)
	var skala := float(img.get_height()) / 1080.0
	if not is_equal_approx(skala, 1.0):
		m.resize(maxi(1, roundi(m.get_width() * skala)), maxi(1, roundi(m.get_height() * skala)), Image.INTERPOLATE_BILINEAR)
	for y in m.get_height():
		for x in m.get_width():
			var c := m.get_pixel(x, y)
			c.a *= deckkraft
			m.set_pixel(x, y, c)
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)
	var rand := roundi(36.0 * skala)
	var pos := Vector2i(img.get_width() - m.get_width() - rand, img.get_height() - m.get_height() - rand)
	if img.get_format() == Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)
		img.blend_rect(m, Rect2i(Vector2i.ZERO, m.get_size()), pos)
		img.convert(Image.FORMAT_RGB8)
	else:
		img.blend_rect(m, Rect2i(Vector2i.ZERO, m.get_size()), pos)

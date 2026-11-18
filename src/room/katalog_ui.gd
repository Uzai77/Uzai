extends "res://src/room/bau_tafel.gd"
## Bau-Menü im Zimmer (wie der Bau-Modus von Die Sims): unten die Leiste der Bereiche als Zeichen –
## links der Raum (Wände und Tapeten, Böden, Decke und Leisten, Fenster und Türen, Licht und
## Stimmung, Raumgröße, Vorlagen), rechts die Möbel nach Zweck (Sitzen, Tische, Regale, Technik,
## Lampen, Pflanzen, Deko, Eigene). Sie steht im Bauen immer da (ruhig, als Dock). Geht das Menü auf
## (A auf leerem Boden, RT), steigt darüber die Tafel mit großen Kacheln (bau_tafel.gd): echte Möbel
## und echte Oberflächen, einmal gerendert (bau_bilder.gd), dazu gezeichnete Fenster, Türen,
## Vorhänge, Stimmungen, Grundrisse und Vorlagen in den Farben des Zimmers.
##
## Erst wählen, dann platzieren: A auf einem Möbel nimmt es an den Cursor im Zimmer, das Menü tritt
## zurück (zimmer_einrichten.gd _platzieren); nach dem Absetzen geht es hier weiter. Eine Tapete, ein
## Boden, eine Stimmung … steht schon beim Wählen als Probe im Zimmer (Signal gewechselt); A
## übernimmt, B nimmt die Probe zurück. Y: Farbe – bei Möbeln die nächste Variante (Tupfer unter
## der Kachel), bei Oberflächen die Farbleiste (Palette, eigene Farben, Farbrad); bei Eigenem die
## Optionen. X macht rückgängig. LB/RB wechselt den Bereich, das Steuerkreuz wählt im Raster.
## Solange das Menü zu ist, wird nichts gerendert (die Bühne der Bilder gibt es dann nicht).
## Seltenes liegt eine Ebene tiefer: „Alle Einstellungen“ öffnet die Seite der Seitenleiste
## (anpassen.gd), danach geht es hierher zurück. Was wo steht: bau_inhalt.gd.

const Katalog := preload("res://src/room/katalog.gd")
const G := preload("res://src/room/gestalt.gd")
const Inhalt := preload("res://src/room/bau_inhalt.gd")
const Bilder := preload("res://src/room/bau_bilder.gd")
const Vorlagen := preload("res://src/room/vorlagen.gd")

const NEU := "+neu"               ## Kachel „Neu bauen“ unter „Eigene“
## Raum-Bereiche (Kennung, Name, Zeichen) – vorn in der Leiste.
const RAUM_TEILE := Inhalt.RAUM

const FARB_D := 44.0              ## Farbleiste: Durchmesser eines Tupfers
const FARB_SCHRITT := 58.0
const FARB_SPALTEN := 16
const RAD := "rad"                ## letzter Tupfer der Farbleiste: Farbrad (Feinseite)

## Himmel je Tageszeit (oben, unten) für Stimmungen, Tageszeit und Wetter.
const HIMMEL := { "morgen": ["#8fb0d4", "#f1c9a2"], "tag": ["#6f9fd0", "#cfe2f0"], "abend": ["#4d5287", "#ee9a62"],
	"nacht": ["#0f1426", "#2c3557"], "auto": ["#6f9fd0", "#cfe2f0"] }
const WETTER_ZEICHEN := { "klar": "sonne", "wolkig": "wolke", "regen": "regen", "schnee": "schnee", "nebel": "nebel" }
const GRIFF := { "messing": "#b8925a", "schwarz": "#2b2b2b", "chrom": "#d6d8db" }

static var _plaene := {}                    ## Vorlage → geprüfter Raum (Grundriss der Kachel)

var wand_ziel := ""                ## Wände: nur diese Seite (Wand im Einrichten gewählt), „“ alle
var _gesperrt := {}               ## Möbel → Bedingung zum Freischalten
var _variante := {}               ## Möbel → gewählte Variante (Y, Tupfer)
var _tupfer_rects: Array = []     ## [Rect2, Index, Variante] (Maus)
var _zuletzt := {}                ## Kachel → zuletzt gezeigtes Bild (kein Flackern beim Neurendern)
var _bild_da := {}                ## Schlüssel → Zeit, seit das Bild da ist (weich einblenden)
var _farben := false              ## Farbleiste offen
var _farben_a := 0.0
var _farb_liste: Array = []
var _farb_sel := 0
var _farb_f := Vector2.ZERO
var _farb_vorher := ""
var _farb_rects: Array = []
var _bilder: Bilder                 ## bau_bilder.gd
var _anfordern_t := 0.0


func _ready() -> void:
	super._ready()
	_kat = Inhalt.RAUM.size()      # Start bei „Sitzen“
	_bilder = Bilder.new()
	add_child(_bilder)
	_bilder.connect("fertig", func(s: String) -> void:
		_bild_da[s] = Time.get_ticks_msec()
		set_process(true)
		queue_redraw())


## Alle Bereiche der Leiste: [Kennung, Name] (Raum zuerst, dann die Möbel).
static func kategorien() -> Array:
	return Inhalt.gruppen().map(func(g: Array) -> Array: return [g[0], g[1]])

static func ist_raum(id: String) -> bool:
	return Inhalt.ist_raum(id)

## Variante eines Möbels, wie sie hier gewählt ist (Y, Tupfer).
func variante(id: String) -> String:
	var v := str(_variante.get(id, ""))
	return v if v != "" and Katalog.variante_gueltig(id, v) else Katalog.std_variante(id)

## Vorschau eines eigenen Möbels vergessen (nach dem Bearbeiten im Baukasten).
static func vergessen(id: String) -> void:
	Bilder.vergessen("m|%s|" % id)

func _raum() -> Dictionary:
	return zimmer.get("raum") if zimmer and zimmer.get("raum") is Dictionary else G.std_raum()

## Stand ohne offene Probe (für das Häkchen „steht im Zimmer“).
func _stand() -> Dictionary:
	if zimmer and zimmer.has_method("bau_stand"):
		return zimmer.call("bau_stand")
	return _raum()

func _daten() -> Dictionary:
	return zimmer.get("daten") if zimmer and zimmer.get("daten") is Dictionary else {}

# --- Bereiche und Kacheln ---------------------------------------------------------------------------

func _gruppen() -> Array:
	return Inhalt.gruppen()


func _trenner() -> int:
	return RAUM_TEILE.size()


func _kacheln_fuer(kat: String) -> Array:
	var out: Array = []
	if ist_raum(kat):
		out = Inhalt.kacheln(kat, _daten())
	else:
		if kat == "eigene":
			out.append({ "id": NEU, "art": "neu" })
		for id in Katalog.in_kategorie(kat):
			out.append({ "id": str(id), "art": "moebel" })
	_gesperrt.clear()
	for k in out:
		if str(k.art) == "moebel":
			var g := str(zimmer.call("gesperrt", k.id)) if zimmer and zimmer.has_method("gesperrt") else ""
			if g != "":
				_gesperrt[k.id] = g
	# Was im vorigen Bereich noch auf ein Bild wartete, fällt weg.
	var schluessel: Array = []
	for k in out:
		var s := _schluessel(k)
		if s != "":
			schluessel.append(s)
	if is_instance_valid(_bilder):
		_bilder.nur_noch(schluessel)
	return out


func _aktiv(k: Dictionary) -> bool:
	return ist_raum(str(k.get("id", ""))) and Inhalt.aktiv(k, _stand(), wand_ziel)


func _geladen() -> void:
	_bilder_anfordern()


## Probe zurück, Farbleiste zu (anderer Bereich, Menü zu).
func _verlassen() -> void:
	if _farben:
		_farben_zu(false, true)
	_verwerfen()


func _jede_runde(dt: float) -> bool:
	_farb_f = _farb_f.lerp(_farb_zelle(_farb_sel), 1.0 - exp(-dt * 16.0))
	_anfordern_t -= dt
	if _anfordern_t <= 0.0:
		_anfordern_t = 0.25
		_bilder_anfordern()
	var jetzt := Time.get_ticks_msec()
	var bilder_ruhig := _bild_da.values().all(func(t: int) -> bool: return jetzt - t > 400)
	var weiter := _farb_f.distance_to(_farb_zelle(_farb_sel)) > 0.002 or not bilder_ruhig or (_farben_a > 0.0 and _farben_a < 1.0)
	if not weiter:
		_bild_da.clear()
	return weiter


## Gleitet von unten herein. behalten: die gewählte Wand bleibt (Wand im Einrichten gewählt, zurück
## aus der Feinseite).
func oeffnen(behalten := false) -> void:
	if not behalten:
		wand_ziel = ""
	super.oeffnen(behalten)


## Zu: was noch auf ein Bild wartete, fällt weg – die Bühne wird frei, das Menü kostet nichts mehr.
func schliessen() -> void:
	super.schliessen()
	if is_instance_valid(_bilder):
		_bilder.nur_noch([])


## Farbe eines Möbels merken, ohne Klang (beim Platzieren mit Y gewechselt).
func variante_merken(id: String, v: String) -> void:
	if Katalog.variante_gueltig(id, v):
		_variante[id] = v
		queue_redraw()


func kategorie_setzen(k: int, richtung := 0) -> void:
	var war := _kat
	super.kategorie_setzen(k, richtung)
	if _kat != war and wand_ziel != "":
		wand_ziel = ""
		queue_redraw()


## Einen Bereich direkt wählen (Wand bzw. Boden im Einrichten gewählt); wand: nur diese Seite. Die
## Wahl steht auf dem, was dort im Zimmer ist.
func bereich(id: String, wand := "") -> void:
	var k := kategorien().map(func(g: Array) -> String: return str(g[0])).find(id)
	if k < 0:
		return
	_verlassen()
	_merk[_kat] = _sel
	_kat = k
	wand_ziel = wand
	_sel = -1
	_angefasst = false
	_laden(0)
	_sel_f = _zelle(_sel)
	_scroll = _ziel_scroll()


func schritt(cmd: String) -> void:
	if _farben:
		_farb_schritt(cmd)
		return
	super.schritt(cmd)


func auffrischen() -> void:
	if _farben:
		_farben_zu(false, true)
	super.auffrischen()


# --- Bilder ---------------------------------------------------------------------------------------

## Schlüssel des Bildes, das eine Kachel jetzt zeigen soll („“: gezeichnet, ohne Bild).
func _schluessel(k: Dictionary) -> String:
	var r := _raum()
	match str(k.get("art", "")):
		"moebel":
			return Bilder.moebel_schluessel(str(k.id), variante(str(k.id)))
		"wand":
			var w: Dictionary = r.waende["hinten" if wand_ziel == "" else wand_ziel]
			var m := str(k.wert)
			var mit_muster := m in ["tapete", "paneel"]
			return Bilder.wand_schluessel(m, str(k.get("mu", "")), str(w.f), str(w.get("mf", "")) if mit_muster else "")
		"boden":
			var a := str(k.wert)
			if str(r.boden.a) == a:
				return Bilder.boden_schluessel(a, str(r.boden.f), str(r.boden.get("f2", "")))
			return Bilder.boden_schluessel(a, str(G.BODEN_STD.get(a, "")), "")
		"decke":
			return Bilder.decke_schluessel("holz" if str(k.wert) == "holz" else "glatt", str(r.decke.f))
	return ""

## Bilder der sichtbaren Reihen (und der nächsten) bestellen; bei offener Farbleiste nur die gewählte.
func _bilder_anfordern() -> void:
	if not is_instance_valid(_bilder) or not _offen:
		return
	if _farben:
		var s0 := _schluessel(kachel())
		if s0 != "":
			_bilder.anfordern(s0, true)
		return
	var gewaehlt_s := _schluessel(kachel())
	if gewaehlt_s != "":
		_bilder.anfordern(gewaehlt_s, true)
	for i in _kacheln.size():
		var reihe := int(_zelle(i).y)
		if reihe >= _scroll_ziel - 1 and reihe <= _scroll_ziel + REIHEN:
			var s := _schluessel(_kacheln[i])
			if s != "":
				_bilder.anfordern(s)

## Bild einer Kachel: das gewünschte, sonst das zuletzt gezeigte (beim Neurendern kein Flackern).
func _bild(k: Dictionary) -> Texture2D:
	var s := _schluessel(k)
	if s == "":
		return null
	var t: Texture2D = _bilder.bild(s)
	if t != null:
		_zuletzt[k.id] = t
		return t
	return _zuletzt.get(k.id)

func _bild_alpha(k: Dictionary) -> float:
	var s := _schluessel(k)
	if not _bild_da.has(s):
		return 1.0
	return clampf(float(Time.get_ticks_msec() - int(_bild_da[s])) / (U.T_BASE * 1000.0), 0.0, 1.0)


# --- Tasten ----------------------------------------------------------------------------------------

## Tasten, die das Menü selbst erledigt (true: verbraucht). Möbel hinstellen, schließen und den
## Bereich wechseln erledigt das Zimmer (_katalog_taste).
func taste(cmd: String) -> bool:
	if _farben:
		match cmd:
			"a", "y":
				if _farb_sel < _farb_liste.size() and str(_farb_liste[_farb_sel]) == RAD:
					_farbrad()
				else:
					_farben_zu(true)
			"b":
				_farben_zu(false)
			"x":
				Sfx.play("bump")
		return cmd != "guide"
	var k := kachel()
	var art := str(k.get("art", ""))
	match cmd:
		"y":
			if art == "moebel" and Katalog.ist_eigen(str(k.id)):
				_seite_auf("eigenes:" + str(k.id))
			elif art == "moebel" and Katalog.varianten(str(k.id)).size() > 1:
				_naechste_variante(str(k.id), 1)
			elif bool(k.get("eigen", false)):
				_seite_auf(Inhalt.seite(k, wand_ziel))
			elif not Inhalt.farbziel(k).is_empty():
				_farben_auf()
			else:
				Sfx.play("bump")
			return true
		"x":
			if zimmer and zimmer.has_method("katalog_rueckgaengig"):
				zimmer.call("katalog_rueckgaengig")
			return true
		"a":
			if not ist_raum(str(k.get("id", ""))):
				return false
			match art:
				"mehr":
					_seite_auf(Inhalt.seite(k, wand_ziel))
				"form", "vorlage":
					if Inhalt.aktiv(k, _stand(), wand_ziel):
						Sfx.play("bump")
					else:
						Sfx.play("select")
						zimmer.call("bau_tun", k)
						auffrischen()
				_:
					# Übernehmen: genau diese Kachel (auch wenn die Probe noch nicht stand) bleibt.
					if not bool(zimmer.call("bau_offen")) and Inhalt.aktiv(k, _stand(), wand_ziel):
						Sfx.play("bump")
						return true
					zimmer.call("bau_probe", k, "", wand_ziel)
					zimmer.call("bau_uebernehmen")
					Sfx.play("select")
					_angefasst = false
			return true
	return false

## Was die Tasten gerade tun (Tastenzeile im Bild): A, Y, X, B – LB/RB stehen an der Leiste.
func hinweise() -> Array:
	if _farben:
		var rad := _farb_sel < _farb_liste.size() and str(_farb_liste[_farb_sel]) == RAD
		return [["a", "Mischen" if rad else "Übernehmen"], ["b", "Zurück"]]
	var h: Array = []
	var k := kachel()
	var id := str(k.get("id", ""))
	match str(k.get("art", "")):
		"neu":
			h.append(["a", "Neu bauen"])
		"moebel":
			var frei := int(zimmer.call("noch_frei", id)) if zimmer and zimmer.has_method("noch_frei") else -1
			if not _gesperrt.has(id) and frei != 0:
				h.append(["a", "Platzieren"])
			if Katalog.ist_eigen(id):
				h.append(["y", "Optionen"])
			elif Katalog.varianten(id).size() > 1:
				h.append(["y", "Farbe"])
		"mehr":
			h.append(["a", "Öffnen"])
		"form", "vorlage":
			if not Inhalt.aktiv(k, _stand(), wand_ziel):
				h.append(["a", "Übernehmen"])
			if bool(k.get("eigen", false)):
				h.append(["y", "Optionen"])
		"":
			pass
		_:
			var offen := zimmer != null and zimmer.has_method("bau_offen") and bool(zimmer.call("bau_offen"))
			if offen or not Inhalt.aktiv(k, _stand(), wand_ziel):
				h.append(["a", "Übernehmen"])
			if bool(k.get("eigen", false)):
				h.append(["y", "Optionen"])
			elif not Inhalt.farbziel(k).is_empty():
				h.append(["y", "Farbe"])
	var rueck: Variant = zimmer.get("_rueck") if zimmer else null
	if rueck is Array and not (rueck as Array).is_empty():
		h.append(["x", "Rückgängig"])
	h.append(["b", "Schließen"])
	return h

func _naechste_variante(id: String, d: int) -> void:
	var vs := Katalog.varianten(id)
	var ids: Array = vs.map(func(p: Array) -> String: return str(p[0]))
	var i := ids.find(variante(id))
	_variante_setzen(id, str(ids[posmod(i + d, ids.size())]))

func _variante_setzen(id: String, v: String) -> void:
	_variante[id] = v
	Sfx.play("move")
	_bilder.anfordern(Bilder.moebel_schluessel(id, v), true)
	set_process(true)
	gewechselt.emit(gewaehlt())

func _seite_auf(kennung: String) -> void:
	if kennung == "" or zimmer == null or not zimmer.has_method("bau_seite"):
		Sfx.play("bump")
		return
	zimmer.call("bau_seite", kennung)

## Offene Probe im Zimmer zurücknehmen (Bereich gewechselt, Menü zu).
func _verwerfen() -> void:
	if zimmer and zimmer.has_method("bau_verwerfen"):
		zimmer.call("bau_verwerfen")


# --- Farbleiste (Y auf einer Oberfläche) -----------------------------------------------------------

func _farben_auf() -> void:
	var k := kachel()
	_farb_liste = G.PALETTE.map(func(p: Array) -> String: return str(p[0]))
	if zimmer and zimmer.has_method("eigene_farben"):
		for c in zimmer.call("eigene_farben"):
			if not (str(c) in _farb_liste):
				_farb_liste.append(str(c))
	_farb_liste.append(RAD)
	_farb_vorher = Inhalt.farbe(k, _raum(), wand_ziel)
	_farb_sel = maxi(0, _farb_liste.find(_farb_vorher))
	_farb_f = _farb_zelle(_farb_sel)
	_farben = true
	Sfx.play("open")
	_farben_blenden()

## zu: übernehmen (true) oder die Farbe von vorher wieder hin; still: ohne Klang.
func _farben_zu(behalten: bool, still := false) -> void:
	_farben = false
	if not behalten and _farb_vorher != "" and zimmer and zimmer.has_method("bau_probe"):
		zimmer.call("bau_probe", kachel(), _farb_vorher, wand_ziel)
	elif behalten and zimmer and zimmer.has_method("bau_uebernehmen"):
		zimmer.call("bau_uebernehmen")
		_angefasst = false
	if not still:
		Sfx.play("select" if behalten else "back")
	_farben_blenden()
	_bilder_anfordern()
	gewechselt.emit(gewaehlt())

func _farben_blenden() -> void:
	U.tw(self, "uz_farben", Tween.TRANS_QUART).tween_method(func(v: float) -> void:
		_farben_a = v
		queue_redraw(), _farben_a, 1.0 if _farben else 0.0, U.T_BASE)
	set_process(true)

func _farb_zelle(i: int) -> Vector2:
	return Vector2(i % FARB_SPALTEN, i / FARB_SPALTEN)

func _farb_schritt(cmd: String) -> void:
	var n := _farb_sel
	match cmd:
		"left": n = _farb_sel - 1 if _farb_sel % FARB_SPALTEN > 0 else -1
		"right": n = _farb_sel + 1 if _farb_sel % FARB_SPALTEN < FARB_SPALTEN - 1 else -1
		"up": n = _farb_sel - FARB_SPALTEN
		"down":
			n = _farb_sel + FARB_SPALTEN
			if n >= _farb_liste.size() and _farb_sel / FARB_SPALTEN < (_farb_liste.size() - 1) / FARB_SPALTEN:
				n = _farb_liste.size() - 1
	_farb_waehlen(n)

func _farb_waehlen(n: int) -> void:
	if n < 0 or n >= _farb_liste.size():
		Sfx.play("bump")
		return
	if n == _farb_sel:
		return
	_farb_sel = n
	Sfx.play("move")
	var hex := str(_farb_liste[n])
	if hex != RAD and zimmer and zimmer.has_method("bau_probe"):
		zimmer.call("bau_probe", kachel(), hex, wand_ziel)
	_bilder_anfordern()
	set_process(true)
	if zimmer and zimmer.has_method("_hinweise_auffrischen"):
		zimmer.call("_hinweise_auffrischen")

## Eigene Farbe mischen: die Feinseite mit dem Farbrad (dort B zurück hierher).
func _farbrad() -> void:
	var k := kachel()
	_farben = false
	_farben_a = 0.0
	var fz := Inhalt.farbziel(k)
	if zimmer and zimmer.has_method("bau_farbrad") and not fz.is_empty():
		zimmer.call("bau_farbrad", Inhalt.seite(k, wand_ziel, true), str(fz[2]))

# --- Zeichnen -----------------------------------------------------------------------------------

func _draw() -> void:
	_tupfer_rects.clear()
	_farb_rects.clear()
	super._draw()


func _kopf_texte() -> Array:
	if _farben_a <= 0.5:
		return _texte(kachel())
	var hex := str(_farb_liste[_farb_sel]) if _farb_sel < _farb_liste.size() else ""
	var titel := tr("Eigene Farbe mischen") if hex == RAD else (tr(G.farbname(hex)) if G.farbname(hex) != "" else hex.to_upper())
	var fz := Inhalt.farbziel(kachel())
	var info := tr(str(fz[2])) if not fz.is_empty() else ""
	if str(kachel().get("art", "")) == "wand" and wand_ziel != "":
		info = tr(str(G.SEITEN_NAMEN.get(wand_ziel, "")))
	return [titel, info]


## Raster und Farbleiste blenden ineinander.
func _inhalt_zeichnen(t: Rect2, a: float) -> void:
	if _farben_a < 0.99:
		_raster(t, a * (1.0 - _farben_a))
	if _farben_a > 0.01:
		_farbleiste(t, a * _farben_a)


func _kachel_zeichnen(k: Dictionary, i: int, r: Rect2, ia: float, gew: bool, rc: int) -> void:
	var art := str(k.get("art", ""))
	var raum := _raum()
	match art:
		"moebel":
			_moebel_kachel(k, i, r, ia, gew, rc)
		"neu":
			_zeichen_kachel(r, ia, gew, rc, "add", "Neu")
		"mehr":
			_zeichen_kachel(r, ia, gew, rc, "settings", "Mehr")
		"wand", "boden", "decke":
			var tex := _bild(k)
			if tex:
				_bild_rund(tex, r, rc, Color(1, 1, 1, ia * _bild_alpha(k)))
				if art == "decke" and str(k.wert) == "balken":
					_balken(r, ia)
				elif art == "decke" and str(k.wert) == "stuck":
					var innen := r.grow(-16.0)
					draw_style_box(_rand_sb(Color(1, 1, 1, 0.5 * ia), rc - 4, 3), innen)
					draw_style_box(_rand_sb(Color(0, 0, 0, 0.12 * ia), rc - 6, 2), innen.grow(-4.0))
			else:
				_flaeche("kachel", r, Stil.KACHEL, ia, rc)
		"sockel":
			_sockel(k, r, ia, rc, raum)
		"fenster", "vorhang":
			_fenster(r, ia, rc, raum, str(k.wert) if art == "fenster" else str(raum.fenster.a), str(k.wert) if art == "vorhang" else "")
		"tuer":
			_tuer(r, ia, rc, raum, str(k.wert))
		"stimmung", "zeit", "wetter":
			_licht_kachel(k, r, ia, rc, raum)
		"form":
			_grundriss(r, ia, rc, raum, int(k.w), int(k.d), [])
		"vorlage":
			_vorlage(k, r, ia, rc, raum)
	# Oberflächen, Fenster, Stimmungen: der Name unten im Bild (vom Sofa aus zu unterscheiden).
	if art in ["wand", "boden", "decke", "sockel", "fenster", "vorhang", "tuer", "stimmung", "zeit", "wetter"]:
		_name_auf_bild(r, ia, rc, str(k.name), bool(k.get("eigen", false)))


## Name und leise Angaben zu einer Kachel.
func _texte(k: Dictionary) -> Array:
	var id := str(k.get("id", ""))
	match str(k.get("art", "")):
		"":
			return ["", ""]
		"neu":
			return [tr("Neu bauen"), tr("Eigenes Möbel im Baukasten")]
		"moebel":
			var titel := Katalog.name_of(id) if Katalog.ist_eigen(id) else tr(Katalog.name_of(id))
			var groesse := Katalog.groesse(id, 0)
			var teile: Array = [tr("%d × %d Felder") % [groesse.x, groesse.y]]
			if Katalog.varianten(id).size() > 1:
				teile.append(tr(Katalog.variante_name(id, variante(id))))
			var frei := int(zimmer.call("noch_frei", id)) if zimmer and zimmer.has_method("noch_frei") else -1
			if frei == 0:
				teile.append(tr("schon im Zimmer"))
			if _gesperrt.has(id):
				teile = [tr("Freischalten: %s") % tr(str(_gesperrt[id]))]
			return [titel, " · ".join(teile)]
	var titel2 := str(k.name) if bool(k.get("eigen", false)) else tr(str(k.name))
	var teile2: Array = [tr(str(k.get("abschnitt", "")))]
	match str(k.art):
		"wand":
			if wand_ziel != "":
				teile2 = [tr(str(G.SEITEN_NAMEN.get(wand_ziel, "")))]
			if str(k.wert) == "tapete":
				titel2 = tr("Tapete") + " · " + titel2
		"form":
			titel2 = tr(str(k.abschnitt)) + " · " + titel2
			teile2 = ["%s × %s m" % [_meter(int(k.w)), _meter(int(k.d))]]
		"vorlage", "mehr":
			if k.has("hinweis"):
				teile2 = [tr(str(k.hinweis))]
	if Inhalt.aktiv(k, _stand(), wand_ziel):
		teile2.append(tr("im Zimmer"))
	return [titel2, " · ".join(teile2.filter(func(s: String) -> bool: return s != ""))]

static func _meter(felder: int) -> String:
	var m := felder * 0.5
	return ("%d" % int(m)) if is_equal_approx(m, roundf(m)) else ("%.1f" % m).replace(".", ",")

func _moebel_kachel(k: Dictionary, i: int, r: Rect2, ia: float, gew: bool, rc: int) -> void:
	var id := str(k.id)
	_flaeche("kachel_g" if gew else "kachel", r, Stil.KACHEL.lightened(0.06) if gew else Stil.KACHEL, ia, rc)
	# Licht von oben hinter dem Möbel, wie auf einer kleinen Bühne.
	var g := _schein()
	draw_texture_rect(g, Rect2(r.position + Vector2(r.size.x * 0.08, -r.size.y * 0.02), r.size * Vector2(0.84, 0.8)), false,
		Color(1.0, 0.9, 0.76, 0.13 * ia))
	var gesperrt := _gesperrt.has(id)
	var voll := zimmer != null and zimmer.has_method("noch_frei") and int(zimmer.call("noch_frei", id)) == 0
	var vs := Katalog.varianten(id)
	var unten := 26.0 if vs.size() > 1 else 10.0
	var seite := minf(r.size.x - 16.0, r.size.y - 6.0 - unten)
	var br := Rect2(Vector2(r.get_center().x - seite * 0.5, r.position.y + 6.0), Vector2(seite, seite))
	var tex := _bild(k)
	if tex:
		var ba := ia * _bild_alpha(k) * (0.4 if gesperrt or voll else 1.0)
		var sch := Bilder.schatten(_schluessel(k))
		if sch.size.x > 0.0:
			var sr := Rect2(br.position + sch.position * br.size, sch.size * br.size)
			sr = sr.grow_individual(sr.size.x * 0.1, sr.size.y * 0.2, sr.size.x * 0.1, sr.size.y * 0.35)
			draw_texture_rect(g, sr, false, Color(0, 0, 0, 0.42 * ba))
		draw_texture_rect(tex, br, false, Color(1, 1, 1, ba))
	else:
		# Noch nicht gerendert: ein ruhiger Platzhalter in fertiger Größe.
		draw_texture_rect(g, br.grow(-br.size.x * 0.2), false, Color(Stil.TINTE, 0.06 * ia))
	# Tupfer: die Varianten, die gewählte mit Ring.
	if vs.size() > 1:
		var n := mini(vs.size(), 7)
		var schritt := 15.0
		var x0 := r.get_center().x - (n - 1) * schritt * 0.5
		var y := r.end.y - 15.0
		var jetzt := variante(id)
		for j in n:
			var v := str(vs[j][0])
			var c := Inhalt.tupfer(v)
			var p := Vector2(x0 + j * schritt, y)
			if c.a <= 0.0:
				c = Stil.LEISE.darkened(0.15 * (j % 3))
			draw_circle(p, 5.0, Color(c, ia), true, -1.0, true)
			draw_arc(p, 5.0, 0, TAU, 20, Color(1, 1, 1, 0.16 * ia), 1.0, true)
			if v == jetzt:
				draw_arc(p, 8.0, 0, TAU, 24, Color(Stil.TINTE, ia), 1.5, true)
			_tupfer_rects.append([Rect2(p - Vector2(7, 7), Vector2(14, 14)), i, v])
	if gesperrt:
		var c2 := br.get_center()
		draw_circle(c2, 22.0, Color(Stil.FLAECHE_HOCH, ia))
		draw_texture_rect(Icons.tex("lock", 24), Rect2(c2 - Vector2(12, 12), Vector2(24, 24)), false, Color(Stil.TINTE, ia))


# --- Gezeichnete Kacheln ----------------------------------------------------------------------------

func _rand_sb(farbe: Color, rc: int, breite: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(breite)
	sb.border_color = farbe
	sb.set_corner_radius_all(maxi(rc, 0))
	sb.anti_aliasing = true
	return sb

static func _farbe(hex: Variant, std: String) -> Color:
	var s := G.farbe(hex)
	return Color(s if s != "" else std)

func _balken(r: Rect2, a: float) -> void:
	var holz := Color("#7a5638")
	for j in 3:
		var y := r.position.y + r.size.y * (0.18 + 0.3 * j)
		var h := 12.0 + 3.0 * j
		draw_rect(Rect2(r.position.x + 2.0, y + h, r.size.x - 4.0, 4.0), Color(0, 0, 0, 0.22 * a))
		draw_rect(Rect2(r.position.x + 2.0, y, r.size.x - 4.0, h), Color(holz, a))
		draw_rect(Rect2(r.position.x + 2.0, y, r.size.x - 4.0, 2.0), Color(holz.lightened(0.25), a))

func _sockel(k: Dictionary, r: Rect2, a: float, rc: int, raum: Dictionary) -> void:
	var wand := _farbe(raum.waende.hinten.f, "#e8e0d1")
	_verlauf(r, rc, Color(wand.lightened(0.04), a), Color(wand.darkened(0.12), a))
	var boden := _farbe(raum.boden.f, "#c29466")
	var by := r.end.y - r.size.y * 0.2
	var bp := _rund_punkte(Rect2(r.position.x, by, r.size.x, r.end.y - by), rc)
	var unten_pkt := PackedVector2Array()
	for q in bp:
		unten_pkt.append(Vector2(q.x, maxf(q.y, by)))
	draw_colored_polygon(unten_pkt, Color(boden, a))
	var hoch := { "schmal": 0.07, "hoch": 0.14, "keine": 0.0 }.get(str(k.wert), 0.07) as float
	if hoch > 0.0:
		var lf := _farbe(raum.sockel.f, "#f1ede6")
		var lr := Rect2(r.position.x, by - r.size.y * hoch, r.size.x, r.size.y * hoch)
		draw_rect(Rect2(lr.position.x, lr.end.y, lr.size.x, 3.0), Color(0, 0, 0, 0.2 * a))
		draw_rect(lr, Color(lf, a))
		draw_rect(Rect2(lr.position, Vector2(lr.size.x, 2.0)), Color(lf.lightened(0.3), a))
	else:
		draw_rect(Rect2(r.position.x, by - 2.0, r.size.x, 2.0), Color(0, 0, 0, 0.18 * a))

## Fenster an der Wand; vorhang: „“ = wie im Zimmer (für Fenster-Kacheln: ohne Vorhang gezeichnet).
func _fenster(r: Rect2, a: float, rc: int, raum: Dictionary, art: String, vorhang: String) -> void:
	var wand := _farbe(raum.waende.links.f, "#e8e0d1")
	_verlauf(r, rc, Color(wand.lightened(0.05), a), Color(wand.darkened(0.1), a))
	var rahmen := _farbe(raum.fenster.rf, "#f3f0ea")
	var breit := art == "panorama"
	var fw := r.size.x * (0.7 if breit else 0.52)
	var fh := r.size.y * (0.56 if breit else 0.6)
	var fr := Rect2(r.get_center().x - fw * 0.5, r.position.y + r.size.y * 0.16, fw, fh)
	if art == "keins":
		art = "sprossen" if vorhang != "" else ""
		if art == "":
			# Ohne Fenster: nur eine zarte Ahnung, wo es war.
			draw_rect(fr, Color(wand.darkened(0.25), 0.35 * a), false, 1.5)
	if art != "":
		draw_rect(Rect2(fr.position + Vector2(3, 4), fr.size), Color(0, 0, 0, 0.14 * a))
		var glas := fr.grow(-5.0)
		var gp := PackedVector2Array([glas.position, Vector2(glas.end.x, glas.position.y), glas.end, Vector2(glas.position.x, glas.end.y)])
		draw_polygon(gp, PackedColorArray([Color("#9fbfdc", a), Color("#9fbfdc", a), Color("#e6eef4", a), Color("#e6eef4", a)]))
		draw_rect(fr, Color(rahmen, a), false, 5.0)
		var sp := Color(rahmen, a)
		match art:
			"sprossen":
				draw_line(Vector2(fr.get_center().x, fr.position.y), Vector2(fr.get_center().x, fr.end.y), sp, 3.0)
				draw_line(Vector2(fr.position.x, fr.position.y + fh * 0.42), Vector2(fr.end.x, fr.position.y + fh * 0.42), sp, 3.0)
			"fluegel":
				draw_line(Vector2(fr.get_center().x, fr.position.y), Vector2(fr.get_center().x, fr.end.y), sp, 4.0)
			"raster":
				for j in 2:
					var xx := fr.position.x + fw * (j + 1) / 3.0
					draw_line(Vector2(xx, fr.position.y), Vector2(xx, fr.end.y), sp, 2.0)
				for j in 3:
					var yy := fr.position.y + fh * (j + 1) / 4.0
					draw_line(Vector2(fr.position.x, yy), Vector2(fr.end.x, yy), sp, 2.0)
		# Fensterbank.
		draw_rect(Rect2(fr.position.x - 6.0, fr.end.y, fw + 12.0, 5.0), Color(rahmen.darkened(0.05), a))
	if vorhang == "" or vorhang == "keine":
		return
	var vf := _farbe(raum.fenster.vf, "#e4d9c6")
	var oben := fr.position.y - 8.0
	draw_line(Vector2(fr.position.x - 16.0, oben), Vector2(fr.end.x + 16.0, oben), Color(0.18, 0.15, 0.13, a), 3.0)
	match vorhang:
		"rollo":
			var rh := fh * 0.45
			draw_rect(Rect2(fr.position.x + 2.0, fr.position.y + 2.0, fw - 4.0, rh), Color(vf, a))
			draw_rect(Rect2(fr.position.x + 2.0, fr.position.y + 2.0 + rh, fw - 4.0, 3.0), Color(vf.darkened(0.25), a))
		_:
			if vorhang == "gardine":
				draw_rect(fr.grow(-4.0), Color(1, 1, 1, 0.42 * a))
			var lang := vorhang != "kurz"
			var bis := r.end.y - 6.0 if lang else fr.end.y + 8.0
			var bw := fw * 0.24
			for seite in [-1, 1]:
				var x0: float = fr.position.x - 12.0 if seite < 0 else fr.end.x + 12.0 - bw
				var vr := Rect2(x0, oben, bw, bis - oben)
				draw_rect(vr, Color(vf, a))
				for j in 3:
					var xx := vr.position.x + vr.size.x * (j + 0.5) / 3.0
					draw_line(Vector2(xx, vr.position.y + 2.0), Vector2(xx, vr.end.y), Color(vf.darkened(0.16), a), 2.0)

func _tuer(r: Rect2, a: float, rc: int, raum: Dictionary, art: String) -> void:
	var wand := _farbe(raum.waende.rechts.f, "#e8e0d1")
	_verlauf(r, rc, Color(wand.lightened(0.05), a), Color(wand.darkened(0.1), a))
	var boden := _farbe(raum.boden.f, "#c29466")
	var by := r.end.y - r.size.y * 0.1
	var bp := _rund_punkte(Rect2(r.position.x, by, r.size.x, r.end.y - by), rc)
	var unten := PackedVector2Array()
	for q in bp:
		unten.append(Vector2(q.x, maxf(q.y, by)))
	draw_colored_polygon(unten, Color(boden, a))
	var tf := _farbe(raum.tuer.f, "#efebe4")
	var tw := r.size.x * 0.42
	var th := r.size.y * 0.74
	var tr_ := Rect2(r.get_center().x - tw * 0.5, by - th, tw, th)
	draw_rect(Rect2(tr_.position - Vector2(5, 5), tr_.size + Vector2(10, 5)), Color(tf.lightened(0.1), a))
	draw_rect(Rect2(tr_.position + Vector2(3, 3), tr_.size), Color(0, 0, 0, 0.12 * a))
	draw_rect(tr_, Color(tf, a))
	var dunkel := Color(tf.darkened(0.14), a)
	match art:
		"kassette":
			for j in 2:
				var ky := tr_.position.y + 10.0 + j * (th * 0.5)
				draw_rect(Rect2(tr_.position.x + 9.0, ky, tw - 18.0, th * 0.5 - 18.0), dunkel, false, 2.5)
		"glas":
			var gl := Rect2(tr_.position.x + 9.0, tr_.position.y + 10.0, tw - 18.0, th * 0.5)
			draw_rect(gl, Color("#bcd2e4", a))
			draw_rect(gl, dunkel, false, 2.5)
		"landhaus":
			for j in 3:
				var xx := tr_.position.x + tw * (j + 1) / 4.0
				draw_line(Vector2(xx, tr_.position.y + 2.0), Vector2(xx, tr_.end.y - 2.0), dunkel, 2.0)
			draw_line(Vector2(tr_.position.x + 4.0, tr_.position.y + th * 0.2), Vector2(tr_.end.x - 4.0, tr_.position.y + th * 0.2), dunkel, 4.0)
			draw_line(Vector2(tr_.position.x + 4.0, tr_.position.y + th * 0.78), Vector2(tr_.end.x - 4.0, tr_.position.y + th * 0.78), dunkel, 4.0)
	var gf := Color(str(GRIFF.get(str(raum.tuer.get("gf", "messing")), "#b8925a")))
	draw_circle(Vector2(tr_.end.x - 9.0, tr_.position.y + th * 0.55), 3.5, Color(gf, a), true, -1.0, true)

## Stimmung, Tageszeit, Wetter: Himmel, Lampenschein, LED-Licht.
func _licht_kachel(k: Dictionary, r: Rect2, a: float, rc: int, raum: Dictionary) -> void:
	var art := str(k.art)
	var zeit := str(raum.licht.z)
	var wetter := str(raum.licht.we)
	var l := {}
	if art == "stimmung":
		l = G.stimmung(str(k.wert))
		if l.is_empty():
			for s in _daten().get("stimmungen", []):
				if str(s.id) == str(k.wert):
					l = s.licht
		zeit = str(l.get("z", zeit))
		wetter = str(l.get("we", wetter))
	elif art == "zeit":
		zeit = str(k.wert)
	elif art == "wetter":
		wetter = str(k.wert)
	var hz: Array = HIMMEL.get(zeit, HIMMEL.tag)
	var grau := wetter in ["wolkig", "regen", "nebel", "schnee"]
	var o := Color(str(hz[0]))
	var u := Color(str(hz[1]))
	if grau:
		o = o.lerp(Color("#9aa1aa"), 0.45 if wetter != "regen" else 0.6)
		u = u.lerp(Color("#c3c7cc"), 0.45)
	_verlauf(r, rc, Color(o, a), Color(u, a))
	var m := r.get_center()
	match art:
		"stimmung":
			# Lampe: Schein in der Farbe der Stimmung, LED-Leiste unten.
			var lf := G.farbe(l.get("lf", ""))
			var lc := Color(lf) if lf != "" else G.kelvin_farbe(float(l.get("k", 2700)))
			var hell := clampf(float(l.get("h", 100)) / 100.0, 0.15, 1.2)
			draw_texture_rect(_schein(), Rect2(m - Vector2(54, 50), Vector2(108, 108)), false, Color(lc, 0.75 * hell * a))
			draw_circle(m + Vector2(0, 4), 9.0, Color(lc.lightened(0.5), a), true, -1.0, true)
			var fa := G.farbe(l.get("fa", ""))
			if fa != "":
				draw_rect(Rect2(r.position.x + 18.0, r.end.y - 16.0, r.size.x - 36.0, 4.0), Color(fa, a))
				draw_texture_rect(_schein(), Rect2(r.position.x + 10.0, r.end.y - 34.0, r.size.x - 20.0, 40.0), false, Color(Color(fa), 0.35 * a))
		"zeit":
			match zeit:
				"auto":
					draw_texture_rect(Icons.tex("clock", 44), Rect2(m - Vector2(22, 22), Vector2(44, 44)), false, Color(1, 1, 1, 0.92 * a))
				"nacht":
					draw_texture_rect(Icons.tex("moon", 40), Rect2(m - Vector2(20, 28), Vector2(40, 40)), false, Color("#f2ead2", a))
				_:
					var sp := { "morgen": Vector2(-30, 16), "tag": Vector2(0, -26), "abend": Vector2(30, 18) }.get(zeit, Vector2.ZERO) as Vector2
					var sc := { "morgen": Color("#ffd9a0"), "tag": Color("#fff6d8"), "abend": Color("#ffb070") }.get(zeit, Color.WHITE) as Color
					draw_texture_rect(_schein(), Rect2(m + sp - Vector2(40, 40), Vector2(80, 80)), false, Color(sc, 0.7 * a))
					draw_circle(m + sp, 13.0, Color(sc, a), true, -1.0, true)
		"wetter":
			var ic := str(WETTER_ZEICHEN.get(wetter, "sonne"))
			draw_texture_rect(Icons.tex(ic, 52), Rect2(m - Vector2(26, 26), Vector2(52, 52)), false, Color(1, 1, 1, 0.94 * a))
	if art != "wetter":
		match wetter:
			"regen":
				for j in 9:
					var p := r.position + Vector2(14.0 + j * 15.0, 18.0 + (j * 37) % 70)
					draw_line(p, p + Vector2(-4, 12), Color(1, 1, 1, 0.35 * a), 1.5, true)
			"schnee":
				for j in 12:
					draw_circle(r.position + Vector2(12.0 + (j * 47) % 124, 14.0 + (j * 29) % 110), 2.0, Color(1, 1, 1, 0.7 * a), true, -1.0, true)

## Grundriss: Raum (w × d Felder) maßstäblich, Boden in seiner Farbe, Wände in ihrer; moebel: Möbel.
func _grundriss(r: Rect2, a: float, rc: int, raum: Dictionary, w: int, d: int, moebel: Array) -> void:
	_flaeche("kachel", r, Stil.KACHEL, a, rc)
	var platz := Rect2(r.position + Vector2(14, 12), r.size - Vector2(28, 42))
	var s := minf(platz.size.x / 20.0, platz.size.y / 20.0)
	var gr := Vector2(w, d) * s
	var pr := Rect2(platz.get_center() - gr * 0.5, gr)
	var boden := _farbe(raum.boden.f, "#c29466")
	draw_rect(pr, Color(boden.darkened(0.08), a))
	for it in moebel:
		var g := Katalog.groesse_it(it)
		var mr := Rect2(pr.position + Vector2(int(it.x), int(it.z)) * s, Vector2(g) * s)
		var c := Inhalt.tupfer(str(it.get("v", "")))
		if c.a <= 0.0:
			c = Color("#d9cbb3")
		var eb := Katalog.ebene(str(it.t))
		if eb == "wand" or eb == "decke":
			continue
		draw_rect(mr.grow(-0.5), Color(c, a * (0.55 if eb == "teppich" else 0.95)))
	var wand := _farbe(raum.waende.hinten.f, "#e8e0d1")
	draw_rect(pr.grow(1.5), Color(wand, a), false, 3.0)
	var fs := UzTheme.size("xs")
	var fo := UzTheme.font("regular")
	var t := "%s × %s m" % [_meter(w), _meter(d)]
	var tw := fo.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(fo, Vector2(r.get_center().x - tw * 0.5, r.end.y - 12.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Stil.LEISE, a))

func _vorlage(k: Dictionary, r: Rect2, a: float, rc: int, raum: Dictionary) -> void:
	var id := str(k.wert)
	var plan: Dictionary = _plaene.get(id, {})
	if plan.is_empty():
		if bool(k.get("eigen", false)):
			for v in _daten().get("vorlagen", []):
				if str(v.id) == id and v.get("raum") is Dictionary:
					plan = v.raum
		else:
			plan = Vorlagen.raum(id)
			_plaene[id] = plan
	if plan.is_empty() or not (plan.get("waende") is Dictionary):
		_grundriss(r, a, rc, raum, int(raum.w), int(raum.d), [])
		return
	_grundriss(r, a, rc, plan, int(plan.get("w", 12)), int(plan.get("d", 10)), plan.get("moebel", []))


# --- Farbleiste -------------------------------------------------------------------------------------

func _farb_rect(t: Rect2, c: Vector2) -> Rect2:
	return Rect2(t.position.x + PAD + 4.0 + c.x * FARB_SCHRITT, t.position.y + KOPF_H + 14.0 + c.y * FARB_SCHRITT, FARB_D, FARB_D)

func _farbleiste(t: Rect2, a: float) -> void:
	for i in _farb_liste.size():
		var r := _farb_rect(t, _farb_zelle(i))
		var hex := str(_farb_liste[i])
		var m := r.get_center()
		_farb_rects.append([r, i])
		if hex == RAD:
			for s in 24:
				var w0 := float(s) / 24.0 * TAU
				draw_arc(m, FARB_D * 0.34, w0, w0 + TAU / 24.0 + 0.02, 4, Color(Color.from_hsv(float(s) / 24.0, 0.8, 0.95), a), 7.0, true)
			draw_line(m + Vector2(-6, 0), m + Vector2(6, 0), Color(Stil.TINTE, a), 2.5, true)
			draw_line(m + Vector2(0, -6), m + Vector2(0, 6), Color(Stil.TINTE, a), 2.5, true)
			continue
		draw_circle(m, FARB_D * 0.5, Color(hex, a), true, -1.0, true)
		draw_arc(m, FARB_D * 0.5 - 0.5, 0, TAU, 40, Color(1, 1, 1, 0.14 * a), 1.0, true)
		if hex == _farb_vorher:
			draw_circle(m, 4.0, Color(UzTheme.text_on(Color(hex)), 0.85 * a), true, -1.0, true)
	if not _farb_liste.is_empty():
		var cr := _farb_rect(t, _farb_f)
		UzTheme.draw_tile_focus(self, cr, int(FARB_D * 0.5), a)

# --- Maus und Finger ----------------------------------------------------------------------------

func _gruppe_klick(k: int) -> void:
	if not _offen and zimmer and zimmer.has_method("katalog_bei"):
		zimmer.call("katalog_bei", k)
	else:
		super._gruppe_klick(k)


## Farbleiste und Tupfer unter den Möbeln.
func _maus(e: InputEvent, p: Vector2) -> bool:
	var farb := -1
	for fr in _farb_rects:
		if (fr[0] as Rect2).has_point(p):
			farb = int(fr[1])
	var klick := e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if _farben:
		if farb >= 0 and farb != _farb_sel:
			_farb_waehlen(farb)
		if klick and farb >= 0:
			accept_event()
			Nav._fire("a")
		return true
	if klick:
		for tr_ in _tupfer_rects:
			if (tr_[0] as Rect2).has_point(p):
				accept_event()
				_waehlen(int(tr_[1]))
				_variante_setzen(str(_kacheln[int(tr_[1])].id), str(tr_[2]))
				return true
	return false

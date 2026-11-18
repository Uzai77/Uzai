extends RefCounted
## Klangdesign mit System (Roadmap 99) – nur Rechnung, keine Knoten, ohne Fenster testbar
## (tests/logic_klang.gd). Sfx und die Menümusik fragen hier:
##
## - Raum: Ein Klang kommt ganz leicht von dort, wo die Auswahl auf dem Bildschirm steht (links im
##   Regal etwas links, rechts etwas rechts). Wie weit, sagt das Theme (`klang.raum`, Standard 0,22
##   von ±1) – nie so weit, dass ein Ohr leer bleibt.
## - Kontext: Tonhöhe und Lautstärke folgen der Lage. Weiter unten in einer Liste klingt das
##   Bewegen eine Spur tiefer, der Anschlag am Listenende (unten/rechts) tiefer und runder als am
##   Anfang (oben/links), Klänge in Ebenen (Seitenleiste, Guide) etwas leiser.
## - Tick (Plan „Gefühl“, Abschnitt 3): Palette, ein Druck ein Klang, Rate beim Blättern,
##   leiser nach langer Ruhe und abends, Richtung beim Bereichswechsel. Sfx fragt hier.
## - Menümusik: selbst erzeugte, ruhige Loops (tools/synth_musik.py, assets/musik). Standardmäßig
##   aus; läuft nur, wenn nichts anderes Ton macht (Spiel, Spielstart, Video, Musik) und Uzai vorn ist.

## Eingebaute Musikstücke: Kennung → Name (sichtbar in den Einstellungen). MUSIK_STD spielt, wenn
## die Einstellung „Standard“ sagt.
const MUSIK := { "ruhe": "Ruhe", "welle": "Welle", "glas": "Glas", "holz": "Holz", "abend": "Abend", "retro": "Retro", "hell": "Hell" }
const MUSIK_STD := "ruhe"
const MUSIK_DIR := "res://assets/musik"

const RAUM_STD := 0.22
const RAUM_MAX := 0.5
## Kontext: wie stark Lage und Rand Tonhöhe und Lautstärke verschieben (bewusst klein).
const TIEFE_LISTE := 0.03       ## Bewegen: oben +1,5 %, unten −1,5 %
const BUMP_ENDE := 0.92         ## Anschlag am Ende (unten/rechts): tiefer
const BUMP_ANFANG := 1.04       ## Anschlag am Anfang (oben/links): eine Spur heller …
const BUMP_ANFANG_LAUT := 0.85  ## … und leiser
const EBENE_LAUT := 0.9

## --- Tick ----------------------------------------------------------------------------------

## Klangsätze: „Handpan“ (Standard, tools/synth_klang5.py, assets/sounds/handpan: eine tiefe, weiche Handpan
## mit rundem Anschlag und Raum in D-Moll pentatonisch – die Vorlage „Tief rund“ aus der Hörprobe; sie klingt
## bewusst nach, darum eigene Höchstlängen statt PALETTE, siehe unten); vier weiche Richtungen aus
## tools/synth_klang4.py (assets/sounds/<Kennung>, alle leiser und dunkler als „Perle“: Bewegen unter 1,5 kHz
## Schwerpunkt, kein Anstieg unter 2 ms, nichts Gläsernes über 5 kHz) – „Samt“ (runde Holz- und
## Filzanschläge, Standard in 0.16), „Kiesel“ (kleine trockene Klicks, Stein auf Stoff), „Pad“ (sanfte
## FM-Zupfer, Bewegen als Luftzug), „Haptik“ (tiefe Taps fast ohne Tonhöhe);
## „Perle“ (tools/synth_klang3.py, assets/sounds/perle: präziser Anschlag, gläserner Kern, Luft und Raum,
## Standard bis 0.16), „Filz & Glas“ (der warme Filz-Körper mit einem kurzen Glas-Schimmer), „Glas kurz“,
## „Filz“ und „Luft“ (tools/synth_klang2.py: warm und kurz, jeder Klang endet mit seiner Bewegung), „Glas“
## (die Klänge bis 0.11, assets/sounds/glas) und „Tick“ (tools/synth_tick.py, assets/sounds). Alle in
## E-Dur pentatonisch außer „Handpan“ und den älteren; Bewegen & Co. haben in den neuen Sätzen mehrere Fassungen.
const SAETZE := [["handpan", "Handpan"], ["samt", "Samt"], ["kiesel", "Kiesel"], ["pad", "Pad"], ["haptik", "Haptik"], ["perle", "Perle"], ["filzglas", "Filz & Glas"],
		["glas", "Glas"], ["glaskurz", "Glas kurz"], ["filz", "Filz"], ["luft", "Luft"], ["tick", "Tick"]]
const SATZ_STD := "handpan"
## Sätze, deren Dateien ihre Staffelung selbst tragen (sonst gilt Sfx.GAIN wie bei „Glas“).
const SAETZE_GESTAFFELT := ["handpan", "samt", "kiesel", "pad", "haptik", "perle", "tick", "filzglas", "glaskurz", "filz", "luft"]
## Ereignisse der Einrichtung (die Sätze aus tools/synth_klang3.py, synth_klang4.py und synth_klang5.py haben eigene Klänge;
## die anderen nehmen dafür einen ihrer Grundklänge, Sfx.ERSATZ_IM_SATZ):
## - setup_step: Schritt weiter. Aufsteigend: Sfx.play("setup_step", Klang.stufe_ton(schritt)).
## - setup_found: etwas gefunden, fliegt ein (Luft kommt näher, kleines Glitzern bei 0,24 s).
## - setup_done: Einrichtung fertig (kurzer, gezupfter Akkord mit Fläche).
## - swell: Licht geht an (Fläche schwillt in 0,76 s an, Filter öffnet sich, heller Glanz oben).
const EINRICHTUNG := ["setup_step", "setup_found", "setup_done", "swell"]
## Tonleiter für aufsteigende Schritte (Dur-pentatonisch, Halbtöne über dem Grundton der Datei).
const STUFEN := [0, 2, 4, 7, 9]
## Die Palette „Tick“, wie tools/synth_tick.py sie rendert (TABELLE dort): Länge ms, Pegel dB
## (Spitze zu „select“), Bewegung ms. Kein Klang ist länger als seine Bewegung + NACHKLANG_MS.
## Die Ereignisse der Einrichtung (EINRICHTUNG) stehen hier so, wie tools/synth_klang3.py und synth_klang4.py
## sie rendern (Pegel dort als Kurzzeit-RMS zu „select“); „Tick“ hat für sie keine eigenen Dateien.
## „Handpan“ (tools/synth_klang5.py) hält sich bewusst nicht an die Längen: Der Ton klingt mit Raum nach
## (Öffnen gut 2,5 s; Bestätigen nur zwei kurze Töne in kleinem Raum, gut 0,8 s – es kommt oft hintereinander),
## Bewegen und Raste sind im Kern so kurz wie hier, nur ihr Raum hallt leise weiter.
## Dort gelten eigene Höchstlängen (TABELLE); Sfx schneidet den Nachklang von Bewegen beim nächsten ab und
## nimmt für neue Klänge zuerst freie oder verstummte Spieler.
const PALETTE := {
	"move": [35, -14.0, 90], "tick": [25, -12.0, 90], "bump": [60, -10.0, 200], "select": [60, 0.0, 90],
	"back": [70, -3.0, 160], "open": [120, 0.0, 360], "toggle_on": [30, -8.0, 90], "toggle_off": [30, -8.0, 90],
	"tab": [90, -8.0, 200], "guide": [140, 1.0, 200], "guide_close": [70, -4.0, 160], "error": [180, -2.0, 200],
	"notify": [200, -4.0, 200], "launch": [350, 0.0, 360], "boot": [1250, 2.0, 2400], "power_off": [920, 0.0, 1400],
	"shutter": [90, -4.0, 160], "achievement": [800, 2.0, 1000], "unlock": [600, 2.0, 1000],
	"unlock_rare": [1000, 2.0, 1200], "unlock_retro": [600, 2.0, 1000],
	"setup_step": [200, -2.0, 200], "setup_found": [420, -3.0, 400], "setup_done": [1200, 2.0, 1200], "swell": [1500, 0.0, 1500],
}
const NACHKLANG_MS := 60

## Ein Druck, ein Klang: Klänge, die so dicht beieinander liegen, gehören zum selben Druck.
const DRUCK_MS := 60
const DRUCK_BILDER := 2         ## … oder höchstens so viele Bilder (ein langsames Bild beim Öffnen)
## Bewegen und Raste: höchstens alle RATE_MS einer; beim Halten (Abstand < HALTEN_MS) bis HALTEN_DB leiser.
const RATE_MS := 70
const HALTEN_MS := 260
const HALTEN_DB := -8.0
const HALTEN_SCHRITTE := 4      ## nach so vielen schnellen Schritten ganz leise
const ZUFALL_TON := 0.015       ## Tonhöhe ±1,5 %
const ZUFALL_DB := 0.5          ## Lautstärke ±0,5 dB
## Nach langer Ruhe (letzte Eingabe über RUHE_MS her): RUHE_DB leiser, in RAMPE_MS wieder voll.
const RUHE_MS := 600000
const RUHE_DB := -6.0
const RAMPE_MS := 3000
## Abends (22–7 Uhr, Uhr des PCs) leiser, ohne Einstellung; Fehler bleiben, wie sie sind.
const ABEND_VON := 22
const ABEND_BIS := 7
const ABEND_DB := -4.0
const ABEND_AUSNAHMEN := ["error"]
## Mitteilung über einem laufenden Spiel: lauter, sonst geht sie unter.
const UEBER_SPIEL_DB := 3.0
## Bereichswechsel: „tab“ kommt aus der Richtung des Wechsels.
const TAB_PAN := 0.3
const RICHTUNG_MS := 300        ## so lange nach LB/RB/LT/RT gilt deren Richtung


## Ordner eines Klangsatzes („tick“ liegt direkt in assets/sounds, die anderen in einem Unterordner).
static func satz_ordner(id: String) -> String:
	return "res://assets/sounds" if id == "tick" else "res://assets/sounds".path_join(id)


## Gehören zwei Klänge zum selben Druck? ms und bilder: Abstand in Millisekunden und Bildern.
static func gleicher_druck(ms: int, bilder: int) -> bool:
	return ms >= 0 and (ms <= DRUCK_MS or (bilder >= 0 and bilder <= DRUCK_BILDER))


## Ein Druck, ein Klang. vorher: die Klänge desselben Drucks als [[Rang, Name], …].
## Der spätere Klang ersetzt die früheren, wenn er mindestens so wichtig ist („open“ ersetzt
## „select“, „tab“ ersetzt „move“); sonst bleibt er still. Gleiche Klänge doppeln sich nie.
## Ergebnis: { spielen: bool, ersetzen: [Indizes in vorher] }.
static func ein_druck(vorher: Array, name: String, rang: int) -> Dictionary:
	var weg: Array = []
	for i in vorher.size():
		var e: Array = vorher[i]
		if str(e[1]) == name or int(e[0]) > rang:
			return { "spielen": false, "ersetzen": [] }
		weg.append(i)
	return { "spielen": true, "ersetzen": weg }


## Bewegen und Raste. abstand: ms seit dem letzten, reihe: so viele schnelle Schritte davor.
## Ergebnis: { ok: bool (überhaupt klingen), reihe: neuer Zähler, db: Abschwächung beim Halten }.
static func bewegen(abstand: int, reihe: int) -> Dictionary:
	if abstand < RATE_MS:
		return { "ok": false, "reihe": reihe, "db": 0.0 }
	var r := reihe + 1 if abstand < HALTEN_MS else 0
	return { "ok": true, "reihe": r, "db": HALTEN_DB * clampf(float(r) / HALTEN_SCHRITTE, 0.0, 1.0) }


## Welche Fassung eines Klangs („Samt“, „Perle“ … haben für Bewegen, Raste, Bestätigen … 2–4 Dateien)? anzahl:
## Fassungen, vorher: die zuletzt gespielte (−1: keine), z: Zufall in 0 … 1. Nie dieselbe zweimal hintereinander.
static func variante(anzahl: int, vorher: int, z: float) -> int:
	if anzahl <= 1:
		return 0
	var zz := clampf(z, 0.0, 0.999999)
	if vorher < 0 or vorher >= anzahl:
		return int(zz * anzahl)
	var k := int(zz * (anzahl - 1))
	return k + 1 if k >= vorher else k


## Tonhöhe (Faktor für Sfx.play) für den Schritt stufe einer aufsteigenden Folge (Einrichtung):
## Dur-pentatonisch über dem Ton der Datei (Stufe 0), höchstens zwei Oktaven (Stufe 10). Die E-Dur-Sätze
## legen den Grundton auf E; „Handpan“ auf F – F G A C D sind die Töne von D-Moll pentatonisch.
static func stufe_ton(stufe: int) -> float:
	var s := clampi(stufe, 0, 10)
	return pow(2.0, float(STUFEN[s % 5] + 12 * int(s / 5.0)) / 12.0)


## Nie zweimal gleich: zufall in −1 … 1 → Vector2(Tonhöhe als Faktor, Lautstärke in dB).
static func zufall(z_ton: float, z_db: float) -> Vector2:
	return Vector2(1.0 + clampf(z_ton, -1.0, 1.0) * ZUFALL_TON, clampf(z_db, -1.0, 1.0) * ZUFALL_DB)


## Nach langer Ruhe leiser. ruhe: ms seit der letzten Eingabe, seit_rampe: ms seit der ersten
## Eingabe nach langer Ruhe (negativ: keine).
static func ruhe_db(ruhe: int, seit_rampe: int) -> float:
	if ruhe > RUHE_MS:
		return RUHE_DB
	if seit_rampe >= 0 and seit_rampe < RAMPE_MS:
		return RUHE_DB * (1.0 - float(seit_rampe) / RAMPE_MS)
	return 0.0


## Abends leiser (stunde: 0 … 23 nach der Uhr des PCs).
static func abend_db(stunde: int, name: String) -> float:
	if name in ABEND_AUSNAHMEN:
		return 0.0
	return ABEND_DB if stunde >= ABEND_VON or stunde < ABEND_BIS else 0.0


## Alles, was zur Lautstärke eines Klangs dazukommt (dB): Abend, Ruhe, Mitteilung über dem Spiel.
static func zusatz_db(name: String, stunde: int, ruhe: int, seit_rampe: int, im_spiel: bool) -> float:
	var d := abend_db(stunde, name) + ruhe_db(ruhe, seit_rampe)
	if name == "notify" and im_spiel:
		d += UEBER_SPIEL_DB
	return d


## Zählt dieses Ereignis als Eingabe (für die Ruhe)? Drücke, Stick deutlich bewegt, Maus bewegt.
static func ist_eingabe(e: InputEvent) -> bool:
	if e is InputEventJoypadButton or e is InputEventKey or e is InputEventMouseButton or e is InputEventScreenTouch:
		return e.is_pressed() and not e.is_echo()
	if e is InputEventJoypadMotion:
		return absf((e as InputEventJoypadMotion).axis_value) > 0.5
	if e is InputEventMouseMotion:
		return (e as InputEventMouseMotion).relative.length() > 2.0
	return false


## Stereo-Lage für den Bereichswechsel: links (LB/LT) oder rechts (RB/RT), sonst null.
static func tab_pan(dir: String) -> Variant:
	match dir:
		"left":
			return -TAB_PAN
		"right":
			return TAB_PAN
	return null


## Menümusik: Lautstärke-Grundwert (Faktor auf den Regler) und Blendzeiten.
const MUSIK_PEGEL_DB := -20.0   ## bei 100 % am Regler: deutlich unter den Menüklängen
const MUSIK_EIN_S := 2.4
const MUSIK_AUS_S := 0.6
const MUSIK_WARTE_S := 1.5      ## so lange muss alles ruhig sein, bevor sie wieder einblendet


## Stereo-Lage (−1 … 1) für einen Punkt x auf einer Breite w. raum: Stärke (üblich RAUM_STD).
static func pan_for(x: float, w: float, raum: float) -> float:
	if not (w > 0.0) or not is_finite(x) or not is_finite(raum):
		return 0.0
	var p := clampf(x / w * 2.0 - 1.0, -1.0, 1.0)
	return p * clampf(raum, 0.0, RAUM_MAX)


## Tonhöhe und Lautstärke nach Kontext: Vector2(Tonhöhe, Lautstärke) als Faktoren.
## name: Klangname, y: Lage von oben (0) bis unten (1) oder -1 (unbekannt), dir: Richtung des
## Anschlags ("up", "down", "left", "right" oder ""), in_layer: Klang aus einer Ebene.
static func kontext(name: String, y: float, dir: String, in_layer: bool) -> Vector2:
	var pitch := 1.0
	var gain := EBENE_LAUT if in_layer else 1.0
	match name:
		"move", "tick":
			if y >= 0.0 and y <= 1.0:
				pitch = 1.0 + (0.5 - y) * TIEFE_LISTE
		"bump":
			if dir == "down" or dir == "right":
				pitch = BUMP_ENDE
			elif dir == "up" or dir == "left":
				pitch = BUMP_ANFANG
				gain *= BUMP_ANFANG_LAUT
	return Vector2(pitch, gain)


## Darf die Menümusik jetzt spielen? zustand: an (Regler > 0), leicht, spiel, startet, video,
## musik (andere Musik läuft), spielklang (der Klang einer Spielseite läuft), vorn (Uzais Fenster
## ist vorn), stueck (es gibt ein Stück).
static func musik_soll(zustand: Dictionary) -> bool:
	if not bool(zustand.get("an", false)) or bool(zustand.get("leicht", false)):
		return false
	if bool(zustand.get("spiel", false)) or bool(zustand.get("startet", false)):
		return false
	if bool(zustand.get("video", false)) or bool(zustand.get("musik", false)) or bool(zustand.get("spielklang", false)):
		return false
	return bool(zustand.get("vorn", true)) and bool(zustand.get("stueck", false))


## Darf der Klang eines Spiels auf seiner Spielseite laufen (src/core/spielklang.gd)? zustand: an
## (Einstellung und iiDB verbunden), laut (Menüklänge nicht stumm), spiel, startet, video, musik
## (eigene Musik läuft – dann schweigt er, statt sich darüberzulegen), vorn.
static func spielklang_soll(zustand: Dictionary) -> bool:
	if not bool(zustand.get("an", false)) or not bool(zustand.get("laut", true)):
		return false
	for k in ["spiel", "startet", "video", "musik"]:
		if bool(zustand.get(k, false)):
			return false
	return bool(zustand.get("vorn", true))


## Welches Stück? wahl: Einstellung ("theme" = Standard oder eine Kennung aus MUSIK).
static func stueck(wahl: String) -> String:
	return wahl if MUSIK.has(wahl) else MUSIK_STD


## Lautstärke der Musik in dB für den Regler (0 … 1).
static func musik_db(regler: float) -> float:
	var v := clampf(regler, 0.0, 1.0)
	if v <= 0.001:
		return -80.0
	return MUSIK_PEGEL_DB + linear_to_db(v)

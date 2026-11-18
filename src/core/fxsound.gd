extends RefCounted
## FxSound (github.com/fxsound2/fxsound-app, AGPL-3.0) von Uzai aus bedienen. FxSound verbessert den Klang für
## alles, was der PC ausgibt: Es legt ein eigenes Ausgabegerät („FxSound Speakers“) als Standardgerät von Windows an,
## bearbeitet, was dort ankommt, und gibt es an das echte Gerät weiter. Uzai bringt FxSound nicht mit und fasst
## weder seinen Treiber noch seine Dateien an – es benutzt nur die Kommandozeile, die FxSound dafür vorsieht
## (docs/COMMAND_LINE_OPTIONS.md dort): Ein Aufruf von FxSound.exe mit Optionen gibt sie an das laufende FxSound
## weiter und endet.
##
##   --power=0|1          Bearbeitung aus/an
##   --preset="Name"      Klangprofil (nur wenn an)
##   --output="Name"      Ausgabegerät – genau der Name, den Windows nennt (derselbe wie in audio-list)
##   --status             schreibt den Stand als JSON nach %APPDATA%\FxSound\status.json
##   --run_minimized      ohne dieses Wort holt jeder Aufruf das Fenster von FxSound nach vorn
##
## Was daraus folgt (im Quelltext von FxSound nachgelesen, FxController.cpp applyConfig):
## - Befehle an ein laufendes FxSound gibt es ab 1.2.10, --status ab 1.2.11 (MIN_VERSION). Ältere bedient Uzai nicht.
## - Läuft FxSound nicht, startet jeder Aufruf es. Uzai schickt darum nur Befehle, wenn es läuft (der Helfer prüft).
## - FxSound zerlegt die Befehlszeile selbst und kennt kein Maskieren: Ein Anführungszeichen im Namen schlösse den
##   Wert und ließe weitere Optionen folgen. Namen mit Anführungszeichen oder Steuerzeichen schickt Uzai nie
##   (wert_ok; der Helfer prüft dasselbe noch einmal, bevor er die Zeile baut).
##
## Hier steht nur, was sich ohne Windows prüfen lässt (tests/logic_fxsound.gd). Aufrufer: src/core/tonwahl.gd.

const Fremd := preload("res://src/core/fremd.gd")

## So heißt FxSounds eigenes Ausgabegerät bei Windows („FxSound Speakers (FxSound Audio Enhancer)“).
const EIGENES_GERAET := "FxSound Audio Enhancer"
const MIN_VERSION := [1, 2, 11]
const NAME_MAX := 64            ## so lang darf ein Klangprofil bei FxSound heißen
const GERAET_MAX := 200
const PROFILE_MAX := 120        ## mehr Profile zeigt Uzai nicht
const GERAETE_MAX := 32
const STATUS_MAX := 512 * 1024  ## größer ist die Statusdatei nie


## Ist das FxSounds eigenes Ausgabegerät? (Steht es bei Windows als Standard, führt FxSound den Ton.)
static func ist_eigenes(name: String) -> bool:
	return name.contains(EIGENES_GERAET)


## Kann diese Fassung Befehle annehmen und ihren Stand melden? „1.2.15.0“ → ja, „1.2.9“ oder Unsinn → nein.
static func version_reicht(v: String) -> bool:
	var teile := v.strip_edges().split(".")
	if teile.size() < 3:
		return false
	for i in 3:
		if not teile[i].is_valid_int() or teile[i].length() > 5:
			return false
		var n := int(teile[i])
		if n != int(MIN_VERSION[i]):
			return n > int(MIN_VERSION[i])
	return true


## Darf dieser Name in einen Befehl? Nicht leer, nicht zu lang, kein Anführungszeichen, keine Steuerzeichen.
static func wert_ok(text: String, laenge := GERAET_MAX) -> bool:
	if text.is_empty() or text.length() > laenge:
		return false
	for i in text.length():
		var c := text.unicode_at(i)
		if c < 32 or c == 127 or c == 34:
			return false
	return true


## Die Statusdatei von FxSound (Text) → { ok, version, an, profil, profile, geraet, geraete }. Fremde Daten: jedes
## Feld geprüft; Namen, die Uzai nicht schicken dürfte, stehen nicht in den Listen (sie wären nicht wählbar).
static func status(text: String) -> Dictionary:
	var out := { "ok": false, "version": "", "an": false, "profil": "", "profile": [], "geraet": "", "geraete": [] }
	if text.is_empty() or text.length() > STATUS_MAX:
		return out
	var d: Variant = Fremd.json(text)
	if not (d is Dictionary):
		return out
	var s: Dictionary = d
	out.ok = true
	out.version = Fremd.text(s.get("version"), "", 32)
	out.an = s.get("power") is bool and bool(s.get("power"))
	var gesehen := {}
	for art in ["built_in", "user_defined"]:
		for p in Fremd.zeilen(s, "presets/" + art):
			var n := Fremd.text((p as Dictionary).get("name")) if p is Dictionary else ""
			if wert_ok(n, NAME_MAX) and not gesehen.has(n) and (out.profile as Array).size() < PROFILE_MAX:
				gesehen[n] = true
				(out.profile as Array).append(n)
	var profil := Fremd.text(s.get("selected_preset"))
	out.profil = profil if wert_ok(profil, NAME_MAX) else ""
	for g in Fremd.liste(s, "output_devices"):
		if g is String and wert_ok(g) and not (out.geraete as Array).has(g) and (out.geraete as Array).size() < GERAETE_MAX:
			(out.geraete as Array).append(g)
	var geraet := Fremd.text(s.get("selected_output"))
	out.geraet = geraet if wert_ok(geraet) else ""
	return out


## Antwort des Helfers auf „fxsound“ → Stand für die Oberfläche:
## { da, laeuft, version, bedienbar, alt, an, profil, profile, geraet, geraete }.
## bedienbar: FxSound läuft, ist neu genug und hat seinen Stand gemeldet. alt: es läuft, ist aber zu alt.
static func stand(r: Dictionary) -> Dictionary:
	var out := { "da": false, "laeuft": false, "version": "", "bedienbar": false, "alt": false, "an": false, "profil": "", "profile": [], "geraet": "",
			"geraete": [] }
	var res: Variant = r.get("result")
	if r.get("ok") != true or not (res is Dictionary):
		return out
	var h: Dictionary = res
	out.da = Fremd.ja(h.get("da"))
	out.laeuft = out.da and Fremd.ja(h.get("laeuft"))
	out.version = Fremd.text(h.get("version"), "", 32)
	out.alt = out.laeuft and not version_reicht(str(out.version))
	var st := status(Fremd.text(h.get("json")))
	if out.laeuft and not out.alt and bool(st.ok):
		out.bedienbar = true
		for k in ["an", "profil", "profile", "geraet", "geraete"]:
			out[k] = st[k]
	return out


## Ein Satz zum Stand, für die Zeile in den Einstellungen und im Mixer.
static func kurz(s: Dictionary) -> String:
	if not bool(s.get("da", false)):
		return "Nicht installiert"
	if not bool(s.get("laeuft", false)):
		return "Läuft nicht"
	if bool(s.get("alt", false)):
		return "Zu alt"
	if not bool(s.get("bedienbar", false)):
		return "Antwortet nicht"
	if not bool(s.get("an", false)):
		return "Aus"
	return str(s.get("profil", "")) if str(s.get("profil", "")) != "" else "An"

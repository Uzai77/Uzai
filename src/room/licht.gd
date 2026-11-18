extends RefCounted
## Licht im Zimmer: das Licht-Konzept und die Grafik-Stufen an einer Stelle. Die Daten, die man
## einstellt (Tageszeit, Wetter, Stimmung, Farbtemperatur, Helligkeit des Raums und jeder Lampe),
## liegen im Zimmer und werden in gestalt.gd geprüft (raum.licht, it.l); zimmer_welt.gd licht_von
## macht daraus Farbe, Helligkeit und Reichweite je Lampe. Hier steht, wie das aussieht:
##
##   ZEITEN: eine klare Hauptquelle durchs Fenster (Sonne bzw. Mond, einziges Licht mit echten
##     Schatten), kühles Himmelslicht als Gegenpart zu den warmen Lampen, ein sanftes Zurückwerfen
##     vom Sonnenfleck (Bounce), wenig Umgebungslicht – damit es hell und dunkel gibt. Das Wetter
##     (raum.gd WETTER) dämpft und färbt das darüber.
##   ART: wie eine Lampe Wände, Boden und Decke anleuchtet (shaders/lichter.gdshaderinc).
##   STIMMUNG_WERTE: was eine Stimmung (gestalt.gd STIMMUNGEN, raum.licht.st) an Belichtung,
##     Kontrast, Sättigung, Vignette und Fernsehlicht dazu gibt; eigene Stimmungen wie „gemütlich“.
##   STUFEN: Grafik Ultra, Hoch, Mittel, Leicht (Config room.grafik, auto am leichten Modus).
##   RENDERER: Forward+ (Vulkan/D3D12) wie früher mit vorberechnetem Licht: Wände, Boden und Decke
##     bekommen ihr Licht aus Lichtkarten, die das Zimmer bei jeder Änderung selbst backt (lichtbacken.gd:
##     weiche Schatten aller Lampen und der Sonne, Himmel als Umgebung, Abprall vom Sonnenfleck).
##     Im laufenden Bild leuchten echte Lichter nur Möbel und Figur (dazu ein warmer Abprall der Lampen
##     als Umgebung), die Reflexionssonde gibt Glanz und wird nur nach einer Änderung neu aufgenommen –
##     keine globale Beleuchtung je Bild (SDFGI, SSIL), keine Spiegelungen im Bild (SSR), kein
##     Volumen-Nebel, kein zeitliches Glätten (gebackenes Licht rauscht nicht): nativ mit MSAA/SMAA.
##     Auto-Belichtung bewusst nicht (sie hob die Nacht auf Tageshelligkeit und macht das Spielbild im
##     Fernseher unbestimmt). Der Kompatibilitäts-Rückfall (OpenGL, alte Karten) rechnet die Hülle im
##     Shader (Lampen, eigene Umgebungsverdeckung).
##
## Ohne Fenster testbar (tests/logic_zgrafik.gd).

## So viele Lampen rechnen die Hüllen-Shader höchstens (die kräftigsten; lichter.gdshaderinc).
const HUELLEN_LAMPEN := 12

## Wie eine Lampe auf Wände, Boden und Decke wirkt: 0 Punkt, 1 Schirm (Licht tritt oben und unten
## aus), 2 Decke (nach unten), 3 Bildschirm (nach vorn). Was fehlt, leuchtet als Punkt.
const ART := { "stehlampe": 1, "tischlampe": 1, "deckenlampe": 2 }
## Farbiges Licht (LED-Leiste): so viel kräftiger wäscht es die Wand an, an der es sitzt – das
## Neonlicht soll die Fläche färben, nicht nur selbst leuchten.
const FARBLICHT_HUELLE := 3.0

## Tageszeiten. Farben als Text, Stärken als Zahl:
##   oben/horizont/huegel  Himmel draußen vor dem Fenster
##   sonne, sonne_e, hoch, seite  Sonne bzw. Mond: Farbe, Stärke, Höhe und Richtung in Grad
##   himmel, himmel_e  kühles Licht, das durchs Fenster fällt (ohne Schatten)
##   decke/wand/boden, amb  Umgebungslicht von oben, von der Seite und vom Boden (Bounce), Stärke
##   bounce  Anteil des Sonnenflecks, der warm zurück in den Raum geworfen wird
##   lampen  wie kräftig Lampen wirken; strahl  wie sichtbar der Lichtstrahl im Fenster ist
##   belichtung  Belichtung (fest, ohne Auto-Belichtung: tagsüber höher, nachts deutlich niedriger –
##     der Raum ist am Tag hell und abends gemütlich dunkel); tief/spitze  Tönung der Schatten und
##     der Lichter (Farbkorrektur); belichtung_kompat  dasselbe im Kompatibilitäts-Renderer (dort
##     leuchtet die Hülle im Shader, ohne SDFGI – die Werte sind darauf abgestimmt)
const ZEITEN := {
	"morgen": { "oben": "#7f9bd0", "horizont": "#f6cfb0", "huegel": "#58664f",
		"sonne": "#ffc894", "sonne_e": 3.0, "hoch": 15.0, "seite": -22.0,
		"himmel": "#b4c2e6", "himmel_e": 0.75, "decke": "#a3a8c2", "wand": "#bfa89c", "boden": "#a08470", "amb": 0.36,
		"bounce": 0.36, "lampen": 0.35, "strahl": 0.7, "nacht": 0.0, "belichtung": 1.5, "belichtung_kompat": 1.08,
		"tief": "#1d2433", "spitze": "#fff1e2" },
	"tag": { "oben": "#5f93d6", "horizont": "#dbe8f2", "huegel": "#4b6845",
		"sonne": "#fff0dc", "sonne_e": 3.0, "hoch": 36.0, "seite": 14.0,
		"himmel": "#c4d7f2", "himmel_e": 1.1, "decke": "#c2cad8", "wand": "#cdc3b4", "boden": "#a89380", "amb": 0.4,
		"bounce": 0.36, "lampen": 0.22, "strahl": 0.32, "nacht": 0.0, "belichtung": 1.75, "belichtung_kompat": 0.88,
		"tief": "#202631", "spitze": "#fffaf0" },
	"abend": { "oben": "#36467a", "horizont": "#f59a5f", "huegel": "#37354a",
		"sonne": "#ff8f48", "sonne_e": 2.7, "hoch": 9.0, "seite": 26.0,
		"himmel": "#7b82bb", "himmel_e": 0.38, "decke": "#4c4e6c", "wand": "#5c5058", "boden": "#6a5040", "amb": 0.2,
		"bounce": 0.4, "lampen": 1.0, "strahl": 1.0, "nacht": 0.0, "belichtung": 0.85, "belichtung_kompat": 1.05,
		"tief": "#1a1c30", "spitze": "#ffe6c8" },
	"nacht": { "oben": "#070c1a", "horizont": "#1d2846", "huegel": "#0e131f",
		"sonne": "#93aef5", "sonne_e": 0.55, "hoch": 32.0, "seite": -12.0,
		"himmel": "#3a4d82", "himmel_e": 0.3, "decke": "#262d46", "wand": "#2a3048", "boden": "#2e2826", "amb": 0.2,
		"bounce": 0.2, "lampen": 1.0, "strahl": 0.45, "nacht": 1.0, "belichtung": 0.65, "belichtung_kompat": 1.22,
		"tief": "#0d1426", "spitze": "#ffe2c2" },
}

## Stimmungen (Kennungen aus gestalt.gd STIMMUNGEN): Tonwerte und Fernsehlicht dazu. Lampen,
## Tageszeit und Wetter setzt die Stimmung selbst (raum.licht); unbekannte und eigene: „“.
const STIMMUNG_WERTE := {
	"": { "belichtung": 1.0, "kontrast": 1.08, "saettigung": 1.1, "tv": 1.0, "vignette": 0.3 },
	"gemuetlich": { "belichtung": 1.0, "kontrast": 1.08, "saettigung": 1.1, "tv": 1.0, "vignette": 0.3 },
	"kino": { "belichtung": 1.25, "kontrast": 1.1, "saettigung": 1.06, "tv": 3.2, "vignette": 0.4 },
	"neon": { "belichtung": 1.3, "kontrast": 1.1, "saettigung": 1.2, "tv": 1.6, "vignette": 0.38 },
	"morgen": { "belichtung": 1.04, "kontrast": 1.04, "saettigung": 1.04, "tv": 0.6, "vignette": 0.2 },
	"tag": { "belichtung": 1.02, "kontrast": 1.04, "saettigung": 1.06, "tv": 0.6, "vignette": 0.16 },
	"winter": { "belichtung": 1.0, "kontrast": 1.06, "saettigung": 1.0, "tv": 1.0, "vignette": 0.32 },
}

## Qualitätsstufen. „auto“: Leicht im leichten Modus, sonst was das Zimmer auf dieser Grafikkarte
## gemessen hat (leistung.gd, Config room.grafik_auto), beim ersten Mal Ultra auf einer starken
## Grafikkarte (STARK), Hoch auf einer anderen eigenen, sonst Mittel. Die Kennungen bleiben (Config room.grafik).
const STUFEN := [["auto", "Automatisch"], ["ultra", "Ultra"], ["hoch", "Hoch"], ["mittel", "Mittel"], ["leicht", "Leicht"]]
## Reihenfolge von der leichtesten zur stärksten (Automatisch: eine Stufe rauf oder runter).
const REIHE := ["leicht", "mittel", "hoch", "ultra"]
##   schatten  Größe der Schattenkarte der Sonne (0 = keine echten Schatten, Sonnenfleck gerechnet)
##   lampen_schatten  so viele Lampen werfen auf Möbel echte Schatten (nur Forward+; die kräftigsten,
##     zimmer_welt.gd; auf der Hülle sind sie gebacken). Die Engine rechnet sie nur neu, wenn sich in
##     ihrer Reichweite etwas bewegt – Figur, Tier, wiegende Pflanzen und Plattenteller werfen darum
##     keine (Kontaktschatten statt dessen): sonst liegen sie still, fast ohne Kosten.
##   upscaler  „nativ“: volle Auflösung (FSR 1 nur als Sicherheitsnetz, wenn die Grafikkarte die Rate
##     nicht hält, aufloesung/leistung.gd); „fsr“ rechnet höchstens FSR_BREITE breit und zieht hoch
##     (FSR 1, billig, für schwache Grafik).
##   msaa  Kantenglättung (dazu SMAA in Ultra und Hoch, aufloesung); taa  zeitliche Kantenglättung
##     (aus: machte das Bild weich, gebackenes Licht braucht sie nicht); skala  obere Grenze der
##     3D-Auflösung (1.0; kleiner nur neben dem laufenden Spiel, spar_werte)
##   ao/dof  Proben der eigenen Umgebungsverdeckung und Tiefenunschärfe (Kompatibilität; 0 = aus)
##   gi  globale Beleuchtung je Bild (SDFGI; aus – gebacken); ssao/ssil/ssr  Umgebungsverdeckung,
##   indirektes Licht und Reflexionen im Bild (nur SSAO, halbe Auflösung); nebel  Volumen-Nebel (aus,
##   der Lichtstrahl ist eine Fläche); sonde  Reflexionssonde (Glanz, neu nur bei Änderung)
##   glow  Glühen der Engine (nur Lampen, hohe Schwelle); schein  Lichtschein an Lampen (Billboards);
##   strahl  Lichtstrahl im Fenster als Fläche (ohne Volumen-Nebel)
const STUFE_WERTE := {
	"ultra": { "schatten": 4096, "lampen_schatten": 2, "upscaler": "nativ", "msaa": 4, "taa": false, "skala": 1.0, "ao": 12, "dof": 16, "gi": false,
		"ssao": true, "ssil": false, "ssr": false, "nebel": false, "sonde": true, "glow": true, "schein": false, "strahl": true },
	"hoch": { "schatten": 4096, "lampen_schatten": 1, "upscaler": "nativ", "msaa": 2, "taa": false, "skala": 1.0, "ao": 12, "dof": 16, "gi": false,
		"ssao": true, "ssil": false, "ssr": false, "nebel": false, "sonde": true, "glow": true, "schein": false, "strahl": true },
	"mittel": { "schatten": 2048, "lampen_schatten": 0, "upscaler": "fsr", "msaa": 2, "taa": false, "skala": 1.0, "ao": 8, "dof": 8, "gi": false,
		"ssao": true, "ssil": false, "ssr": false, "nebel": false, "sonde": true, "glow": true, "schein": true, "strahl": true },
	"leicht": { "schatten": 0, "lampen_schatten": 0, "upscaler": "fsr", "msaa": 0, "taa": false, "skala": 1.0, "ao": 0, "dof": 0, "gi": false,
		"ssao": false, "ssil": false, "ssr": false, "nebel": false, "sonde": false, "glow": false, "schein": true, "strahl": false },
}
## Nativ (Ultra, Hoch): kleinste Skala des Sicherheitsnetzes (FSR 1) je Höhe des Bildschirms:
## [ab Höhe, Ultra, Hoch]. Gerechnet wird voll; kleiner nur, wenn die Grafikkarte die Rate nicht hält.
const NATIV_MIN := [[1800, 0.77, 0.67], [1300, 0.77, 0.77], [0, 0.87, 0.87]]
## Mittel und Leicht (FSR 1): so breit (Bildpunkte) rechnet die 3D-Ansicht höchstens; kleinste Skala.
const FSR_BREITE := 2560
const FSR_MIN := 0.6
## Eigene Grafikkarte (nicht im Prozessor): Namen, an denen „auto“ sie erkennt.
const DISKRET := ["geforce", "rtx", "gtx", "quadro", "radeon rx", "radeon pro", "arc a", "arc b"]
## Starke Grafikkarten: „auto“ beginnt dort mit Ultra (die Messung korrigiert es ab dem nächsten Betreten).
const STARK := ["rtx 4070 ti", "rtx 4080", "rtx 4090", "rtx 5070", "rtx 5080", "rtx 5090", "rx 7900", "rx 9070"]


# --- Lampe, Stimmung, Tageszeit, Stufe ------------------------------------------------------------

static func art(t: String) -> int:
	return int(ART.get(t, 0))


## Tonwerte der Stimmung des Raums (raum.licht.st).
static func stimmung(raum: Dictionary) -> Dictionary:
	var l: Variant = raum.get("licht", {})
	var st := str((l as Dictionary).get("st", "")) if l is Dictionary else ""
	return STIMMUNG_WERTE.get(st, STIMMUNG_WERTE[""])


static func zeit(name: String) -> Dictionary:
	return ZEITEN.get(name, ZEITEN.tag)


## Welche Stufe gilt: wahl aus room.grafik, leicht = leichter Modus an, karte = Name der Grafikkarte,
## gelernt = was „Automatisch“ auf dieser Karte gemessen hat ({ karte, stufe }, leistung.gd).
## Im Kompatibilitäts-Renderer gibt es kein Ultra (nichts davon ginge dort): dann Hoch.
static func stufe_jetzt(wahl: String, leicht: bool, karte := "", renderer := "", gelernt: Variant = null) -> String:
	var r := renderer if renderer != "" else renderer_jetzt()
	if STUFE_WERTE.has(wahl):
		return "hoch" if wahl == "ultra" and r == "compat" else wahl
	if leicht:
		return "leicht"
	if gelernt is Dictionary and str((gelernt as Dictionary).get("karte", "")) == karte and karte != "" \
			and STUFE_WERTE.has(str((gelernt as Dictionary).get("stufe", ""))):
		var g := str((gelernt as Dictionary).stufe)
		return "hoch" if g == "ultra" and r == "compat" else g
	var n := karte.to_lower()
	for k in STARK:
		if k in n:
			return "hoch" if r == "compat" else "ultra"
	for k in DISKRET:
		if k in n:
			return "hoch"
	return "mittel"


## Nächste Stufe in REIHE (richtung +1 stärker, -1 leichter); am Rand bleibt sie.
static func stufe_daneben(stufe: String, richtung: int) -> String:
	var i := REIHE.find(stufe)
	if i < 0:
		return stufe
	return str(REIHE[clampi(i + richtung, 0, REIHE.size() - 1)])


## Wie die 3D-Ansicht gerechnet wird (w = werte(), breite/hoehe des Bildschirms in Bildpunkten):
## { modus: "fsr" | "bilinear", aa: "smaa" | "", msaa, start, max, min } – Skalen der Breite und Höhe.
## Forward+ nativ (Ultra, Hoch) mit MSAA und SMAA, FSR 1 nur als Sicherheitsnetz bis NATIV_MIN; FSR 1
## (Mittel, Leicht) höchstens FSR_BREITE breit; Kompatibilität fest (bilinear, ab 2560 hochgezogen).
static func aufloesung(w: Dictionary, breite: int, hoehe: int) -> Dictionary:
	var grenze := float(w.get("skala", 1.0))
	var breit := minf(1.0, float(FSR_BREITE) / float(maxi(breite, 1)))
	if str(w.get("renderer", "")) != "forward":
		var k := minf(grenze, breit if str(w.get("upscaler", "")) == "fsr" else 1.0)
		return { "modus": "bilinear", "aa": "", "msaa": int(w.get("msaa", 0)), "start": k, "max": k, "min": k }
	if str(w.get("upscaler", "")) == "nativ":
		var lo := 1.0
		for z: Array in NATIV_MIN:
			if hoehe >= int(z[0]):
				lo = float(z[1] if str(w.get("stufe", "")) == "ultra" else z[2])
				break
		var g := minf(1.0, maxf(grenze, lo))
		return { "modus": "fsr", "aa": "smaa", "msaa": int(w.get("msaa", 0)), "start": g, "max": g, "min": minf(g, lo) }
	var m := minf(grenze, breit)
	return { "modus": "fsr", "aa": "", "msaa": int(w.get("msaa", 0)), "start": m, "max": m, "min": minf(m, FSR_MIN) }


## Welcher Renderer läuft: "forward" (Forward+ oder Mobile, Vulkan/D3D12) oder "compat" (OpenGL).
## Ohne Fenster (Tests, Server) gilt "forward" – die Werte sind dann ohnehin nur Zahlen.
static func renderer_jetzt() -> String:
	var m := RenderingServer.get_current_rendering_method()
	return "compat" if m == "gl_compatibility" else "forward"


## Sparsam neben einem laufenden Spiel (aufgestanden im Zimmer, das Spiel läuft im Fernseher weiter):
## dieselbe Stufe, aber ohne das Teuerste – keine Lampenschatten, Sonnenschatten höchstens 2048 und ohne
## weiche PCSS-Kanten, kein SSIL, kein SSR, kein Volumen-Nebel, MSAA höchstens 2×, und auf großen
## Bildschirmen (breite in Pixeln) eine kleinere 3D-Auflösung (FSR 1, schärft nach). SSAO und GI
## bleiben (nur mit weniger Proben, zimmer_basis.gd), damit der Raum nicht anders aussieht. Leicht
## bleibt Leicht. Ist das Spiel aus, gilt wieder die Stufe.
static func spar_werte(w: Dictionary, breite: int) -> Dictionary:
	var s := w.duplicate()
	s.msaa = mini(int(w.get("msaa", 0)), 2)
	s.lampen_schatten = 0
	s.schatten = mini(int(w.get("schatten", 0)), 2048)
	s.ssil = false
	s.ssr = false
	s.nebel = false
	var skala := 1.0
	if breite >= 3000:
		skala = 0.67
	elif breite >= 2200:
		skala = 0.8
	s.skala = minf(float(w.get("skala", 1.0)), skala)
	s["pcss"] = false
	s["spar"] = true
	return s


## Die Werte einer Stufe, auf den Renderer gerechnet: Kompatibilität kann weder GI noch SSAO, SSIL,
## SSR, TAA, Nebel oder Sonde – dort bleiben die eigenen Wege (ao, msaa, schein, strahl). Forward+
## braucht die eigene Umgebungsverdeckung nicht (ao = 0), die Lichtscheine ersetzt das Glühen.
static func werte(stufe: String, renderer := "") -> Dictionary:
	var w: Dictionary = (STUFE_WERTE.get(stufe, STUFE_WERTE.mittel) as Dictionary).duplicate()
	var r := renderer if renderer != "" else renderer_jetzt()
	if r == "compat":
		for k in ["gi", "ssao", "ssil", "ssr", "nebel", "sonde", "taa"]:
			w[k] = false
		w.lampen_schatten = 0
		w.skala = 1.0 if float(w.skala) > 0.8 else float(w.skala)
		if stufe != "leicht":
			w.schein = true
			w.strahl = true
	else:
		w.ao = 0 if bool(w.ssao) else int(w.ao)
		w.msaa = 0 if bool(w.taa) else int(w.msaa)
	w["renderer"] = r
	w["stufe"] = stufe if STUFE_WERTE.has(stufe) else "mittel"
	return w

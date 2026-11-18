extends RefCounted
## Leichter Modus (Punkt 65): Uzai auf schwachen PCs – ältere Laptops, Software-Grafik, kleine
## integrierte Grafik – ruhig und flüssig. Dasselbe Menü, dieselbe Bedienung; nur die teuren Teile
## werden einfacher: Cover schneiden ihr Bild eckig zu statt über einen eigenen Puffer, Schatten
## und Glimmen werden kürzer, die Lichter im Hintergrund stehen still, Animationen laufen etwas
## kürzer, Bilder liegen kleiner im Speicher, und das Menü zeichnet höchstens 60 Bilder je
## Sekunde (nach einer Weile ohne Eingabe 30).
##
## Einstellung display.light: „aus“, „auto“ (Standard: Uzai beobachtet und schlägt ihn einmal
## ruhig vor, schaltet aber nie still um) oder „an“. Alle Werte, die der Modus ändert, stehen
## hier; die Bauteile fragen nur Leicht.active. Ohne Fenster testbar (tests/logic_leicht.gd).
##
## Gemessen mit Software-Grafik als Stellvertreter für einen schwachen PC (Mesa llvmpipe,
## 1920 × 1080, tests/probe_leicht.gd, Median, aus und an abwechselnd): Startseite etwa ein
## Drittel schneller je Bild, Guide etwa ein Viertel. Der größte Posten waren die Cover-Reihen
## (clip_children: ein eigener Zeichenpuffer je Cover), danach Schatten und Weichzeichner.

const Lang := preload("res://src/core/lang.gd")

const MODES := [["aus", "Aus"], ["auto", "Automatisch"], ["an", "An"]]

## Was der Modus ändert – die Bauteile lesen diese Werte:
const ANIM_SPEED := 1.4          ## Animationen über U.tw rund ein Drittel kürzer
const SHADOW_K := 0.5            ## Schatten und Glimmen halb so weit (UzTheme.lift, with_glow, Cover)
const BLUR_TAPS := 4             ## Weichzeichner mit 4 statt 12 Proben je Bildpunkt (Background.blur_taps)
const COVER_RADIUS := 4          ## Ecken der Cover und Kacheln, die ihr Bild eckig zuschneiden (U.clip_round)
const MENU_FPS_MAX := 60         ## Menü höchstens so viele Bilder je Sekunde …
const IDLE_FPS_MAX := 30         ## … und nach IDLE_MS ohne Eingabe höchstens so viele
const IDLE_MS := 20000
const TEX_BUDGET_K := 0.5        ## Bilder auf der Grafikkarte: halbes Budget (Media)
const PREBUILD_MAX := 2          ## nur die beiden Nachbarbereiche der Startseite vorbauen

## Woran Uzai einen schwachen PC erkennt. Gemessen wird nur das sichtbare Menü (Perf).
const MIN_FRAMES := 3000         ## erst nach so vielen gemessenen Bildern urteilen (gut 50 s bei 60 Hz)
const LATE_STRONG := 10.0        ## so viel % der Bilder zu spät: ruckelt deutlich (Ziel: unter 1 %)
const LATE_WEAK := 3.0           ## mit schwacher Ausstattung reicht schon das
const FEW_CORES := 2
const LITTLE_RAM_MB := 6144
## Software-Grafik (kein Treiber für die Grafikkarte): Name des Geräts.
const SOFTWARE := ["llvmpipe", "softpipe", "swiftshader", "microsoft basic render", "gdi generic"]

## Der Modus ist an (aus display.light, siehe refresh). Bauteile lesen nur das.
static var active := false
## Das Menü ruht gerade mit IDLE_FPS_MAX (main). Perf zählt dann nicht.
static var idle := false


## display.light neu lesen (beim Start und wenn sich die Einstellung ändert).
static func refresh() -> void:
	active = str(Config.get_value("display.light", "auto")) == "an"


## Höchstens so viele Bilder je Sekunde im Menü, und zwar so, dass jedes Bild gleich viele
## Bildwechsel stehen bleibt (120 Hz → 60, 144 Hz → 48, 165 Hz → 55). 0 = keine Grenze.
static func menu_fps(hz: float, most := MENU_FPS_MAX) -> int:
	if not (hz > 1.0):     # unbekannt (auch NaN): wie 60 Hz
		hz = 60.0
	if hz <= most + 0.5:
		return 0
	return roundi(hz / ceilf(hz / most))


## Ruhendes Menü (nichts bewegt sich, niemand drückt): halbe Rate bei 60 Hz, sonst wie menu_fps.
static func idle_fps(hz: float) -> int:
	if not (hz > 1.0):     # unbekannt (auch NaN): wie 60 Hz
		hz = 60.0
	return roundi(hz / ceilf(hz / IDLE_FPS_MAX))


## Was Uzai über diesen PC weiß, ohne zu fragen: Name der Grafik, Kerne, Arbeitsspeicher.
static func device() -> Dictionary:
	var mem := OS.get_memory_info()
	var phys := int(mem.get("physical", -1))
	return {
		"adapter": RenderingServer.get_video_adapter_name(),
		"cores": OS.get_processor_count(),
		"ram_mb": phys / 1048576 if phys > 0 else 0,
	}


## Gründe für den leichten Modus aus den Gerätedaten und der Messung im Menü (Perf.frame_stats).
## Vorsichtig: Integrierte Grafik allein ist kein Grund – aktuelle sind schnell genug. Ein
## Grund ist Software-Grafik, ein deutlich ruckelndes Menü oder wenig Ausstattung zusammen mit
## leichtem Ruckeln. Leer = nichts vorschlagen.
static func reasons(info: Dictionary, menu: Dictionary) -> Array:
	var out: Array = []
	var name := str(info.get("adapter", "")).to_lower()
	for w in SOFTWARE:
		if name.contains(w):
			out.append("software")
			break
	if int(menu.get("frames", 0)) >= MIN_FRAMES:
		var late := float(menu.get("late_pct", 0.0))
		var cores := int(info.get("cores", 0))
		var ram := int(info.get("ram_mb", 0))
		if late >= LATE_STRONG:
			out.append("ruckelt")
		elif late >= LATE_WEAK and ((cores > 0 and cores <= FEW_CORES) or (ram > 0 and ram < LITTLE_RAM_MB)):
			out.append("schwach")
	return out


## Einmal vorschlagen: nur bei „Automatisch“, nur wenn es einen Grund gibt und noch nie gefragt.
static func should_suggest(setting: String, asked: bool, why: Array) -> bool:
	return setting == "auto" and not asked and not why.is_empty()


## Ein Satz, warum Uzai den Modus vorschlägt.
static func reason_text(why: Array, menu: Dictionary) -> String:
	if why.has("software"):
		return "Dieser PC zeichnet ohne Grafiktreiber (Software-Grafik)."
	if why.has("ruckelt") or why.has("schwach"):
		return "Das Menü ruckelt hier: %s der Bilder kamen zu spät." % Lang.dec("%.0f %%" % float(menu.get("late_pct", 0.0)))
	return ""


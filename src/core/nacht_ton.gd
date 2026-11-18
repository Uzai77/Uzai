extends Node
## Nachts leiser (Einstellungen → Klang): von system.nacht_von bis system.nacht_bis Uhr hält Uzai
## die Gesamtlautstärke von Windows höchstens auf system.nacht_laut Prozent. Einmal je Minute
## nachgesehen (master-set ohne Wert liest nur); Uzai senkt nur, nie lauter, und der Mixer geht
## nachts nicht über die Grenze (Mixer.set_level). Nur die Gesamtlautstärke über den Helfer, wie
## der Regler von Windows – Fernseher und Verstärker regeln selbst. Hängt an Mixer.
## Logik statisch, ohne Windows testbar (tests/logic_komfort.gd).

const STUFEN := [["aus", "Aus"], ["20", "20 %"], ["30", "30 %"], ["40", "40 %"], ["50", "50 %"]]
const VON := [["20", "20 Uhr"], ["21", "21 Uhr"], ["22", "22 Uhr"], ["23", "23 Uhr"], ["0", "0 Uhr"]]
const BIS := [["5", "5 Uhr"], ["6", "6 Uhr"], ["7", "7 Uhr"], ["8", "8 Uhr"], ["9", "9 Uhr"]]
const TICK_S := 60.0

var _busy := false
var _gemeldet := false          ## in diesem Nachtfenster schon gesagt, dass Uzai leiser gestellt hat


func _ready() -> void:
	var t := Timer.new()
	t.wait_time = TICK_S
	t.timeout.connect(pruefen)
	add_child(t)
	t.start()
	Config.changed.connect(func(k: String) -> void:
		if k.begins_with("system.nacht_"):
			pruefen()
	)


## Liegt die Stunde im Fenster [von, bis)? Über Mitternacht (22 → 7) wie erwartet; von == bis: nie.
static func im_fenster(stunde: int, von: int, bis: int) -> bool:
	if von == bis:
		return false
	if von < bis:
		return stunde >= von and stunde < bis
	return stunde >= von or stunde < bis


## Grenze in Prozent zu dieser Stunde, -1 = keine.
static func grenze_bei(stufe: String, von: int, bis: int, stunde: int) -> int:
	if not stufe.is_valid_int():
		return -1
	return clampi(int(stufe), 5, 100) if im_fenster(stunde, clampi(von, 0, 23), clampi(bis, 0, 23)) else -1


## Grenze jetzt (Einstellungen und Ortszeit), -1 = keine.
static func jetzt() -> int:
	var h := int(Time.get_datetime_dict_from_system().get("hour", 12))
	return grenze_bei(str(Config.get_value("system.nacht_laut", "aus")), int(str(Config.get_value("system.nacht_von", "22"))),
			int(str(Config.get_value("system.nacht_bis", "7"))), h)


## Auf welchen Pegel senken (-1 = nichts tun): nur, wenn er über der Grenze liegt.
static func senken_auf(pegel: int, grenze: int) -> int:
	return grenze if grenze >= 0 and pegel > grenze else -1


## Pegel, den der Mixer setzen darf (nachts höchstens die Grenze).
static func begrenzt(pegel: int) -> int:
	var g := jetzt()
	return mini(pegel, g) if g >= 0 else pegel


## Läufe von pruefen, die gerade unterwegs sind (siehe dort).
var _pruefen_offen := 0


## Gesamtlautstärke lesen und, wenn nötig, senken. Nur unter Windows mit Helfer.
func pruefen() -> void:
	_pruefen_offen += 1
	await _pruefen_lauf()
	_pruefen_offen -= 1
	# Bricht der Lauf mit einem Skriptfehler ab, geht es hier trotzdem weiter (gemessen). Die Marke bliebe sonst für
	# immer stehen, und pruefen täte bis zum Neustart nichts mehr.
	if _pruefen_offen == 0 and _busy:
		_busy = false


func _pruefen_lauf() -> void:
	var g := jetzt()
	if g < 0:
		_gemeldet = false
		return
	if _busy or not Config.is_windows() or not Helper.available:
		return
	_busy = true
	var r: Dictionary = Mixer.parse_set(await Helper.run("master-set", { "level": -1, "mute": -1 }, 4.0))
	var ziel := senken_auf(int(r.get("level", -1)), g) if bool(r.get("found", false)) else -1
	if ziel >= 0:
		await Helper.run("master-set", { "level": ziel, "mute": -1 }, 4.0)
		Helper.hlog("Nachts leiser: Gesamtlautstärke %d → %d %%" % [int(r.level), ziel])
		if not _gemeldet:
			_gemeldet = true
			Toasts.show_toast("Nachts leiser", TranslationServer.translate("Lautstärke auf %d %%") % ziel, "volume_down",
					{ "quiet": true, "ms": 3000, "overlay": true })
	_busy = false

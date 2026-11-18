extends Control
## Songtext neben „Läuft gerade“: die laufende Zeile groß und hell, die nächsten leiser, die
## vergangenen verblassen. Die Fläche gleitet weich mit (zeitgenaue Zeilen von LRCLIB); ohne
## Zeitangaben steht der Text ruhig da. Oben und unten läuft der Text weich aus.

const Lyrics := preload("res://src/core/lyrics.gd")
const Zustand := preload("res://src/core/zustand.gd")
const FS := 34
const FS_SMALL := 30
const GAP := 22.0
## Songtext zum laufenden Titel: lädt, dann da, keiner, Fehler oder aus; ein neuer Titel lädt neu.
const ZUSTAENDE := { "*": ["laedt"], "laedt": ["ok", "keine", "fehler", "aus"], "ok": [], "keine": [], "fehler": [], "aus": [] }

var _key := ""
var _data: Dictionary = {}
var _state := "laedt":
	set(neu):
		Zustand.wechsel("musik.songtext", ZUSTAENDE, _state, neu)
		_state = neu
var _scroll := 0.0
var _idx := -1
var _zeilen: PackedStringArray = []     ## Text je Zeile (leere als „♪“)
var _oben: PackedFloat32Array = []      ## Oberkante je Zeile ohne Rollen (klein gesetzt); am Ende die ganze Höhe
var _mass_w := -1.0                     ## für diese Breite gemessen (-1: neu messen)
var _gezeichnet := 0.0                  ## Rollstand des letzten Bilds


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	custom_minimum_size = Vector2(560, 520)
	Music.updated.connect(_check)
	_check()


## Anzeige weg (Seite gewechselt, Neuaufbau): ihr Stand aus Zustand.lage() (kein alter Stand im Fehlerbericht).
func _exit_tree() -> void:
	Zustand.vergessen("musik.songtext")


func _check() -> void:
	var now: Dictionary = Music.now
	var key := "%s|%s" % [str(now.get("title", "")), str(now.get("artist", ""))]
	if key == _key:
		return
	_key = key
	_data = {}
	_mass_w = -1.0
	_state = "laedt"
	_idx = -1
	_scroll = 0.0
	queue_redraw()
	if str(now.get("title", "")) == "":
		_state = "keine"
		return
	var me: WeakRef = weakref(self)
	var res: Dictionary = await Lyrics.fetch(str(now.get("title", "")), str(now.get("artist", "")), str(now.get("album", "")), int(now.get("duration", 0)))
	var s: Object = me.get_ref()
	if s == null or key != _key:
		return
	_data = res
	_mass_w = -1.0
	_state = str(res.get("state", "keine"))
	queue_redraw()


func _process(dt: float) -> void:
	if not is_visible_in_tree() or _state != "ok":
		return
	_messen()
	if _zeilen.is_empty():
		return
	var synced: Array = _data.get("synced", [])
	var i := -1
	var target := 0.0
	if synced.is_empty():
		# Ohne Zeitangaben gleitet der Text mit dem Lied mit (Anfang oben, Ende unten) – sonst sähe
		# man von einem langen Text nur die ersten Zeilen, und rollen kann man hier nicht.
		var dur := float(Music.now.get("duration", 0))
		var ueber := _oben[_zeilen.size()] + 40.0 - size.y * 0.7
		if dur > 0.0 and ueber > 0.0:
			target = ueber * clampf(float(Music.progress_ms()) / dur, 0.0, 1.0)
	else:
		# Die laufende Zeile steht auf einem Drittel der Höhe – nach ihrer echten Lage, nicht nach
		# einer geschätzten Zeilenhöhe (bei langen Liedern lief sie sonst aus dem Bild).
		i = Lyrics.line_at(synced, Music.progress_ms() + 250)
		target = maxf(0.0, _oben[clampi(i, 0, _zeilen.size() - 1)] - size.y * 0.32)
	_scroll = lerpf(_scroll, target, 1.0 - exp(-dt * 6.0))
	if i != _idx or absf(_scroll - _gezeichnet) >= 1.0:
		_idx = i
		queue_redraw()


## Zeilen und ihre Lage einmal je Text und Breite messen (nicht in jedem Bild: ein Lied hat gut
## 60 Zeilen). Songtext ist fremder Text und wird nie übersetzt (kein tr()).
func _messen() -> void:
	var w := size.x - 8.0
	if is_equal_approx(w, _mass_w):
		return
	_mass_w = w
	_zeilen = PackedStringArray()
	_oben = PackedFloat32Array()
	var synced: Array = _data.get("synced", [])
	if synced.is_empty():
		for l in _data.get("plain", PackedStringArray()):
			_zeilen.append(_zeile(str(l)))
	else:
		for e in synced:
			_zeilen.append(_zeile(str(e[1])))
	var font := UzTheme.display("black")
	var y := 0.0
	for t in _zeilen:
		_oben.append(y)
		y += font.get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, w, FS_SMALL).y + GAP
	_oben.append(y)


static func _zeile(t: String) -> String:
	return "♪" if t.strip_edges() == "" else t


func _draw() -> void:
	var font := UzTheme.display("black")
	var w := size.x - 8.0
	if _state != "ok":
		var msg: String = { "laedt": "Songtext lädt …", "keine": "Für diesen Titel gibt es keinen Songtext.", "fehler": "Songtext gerade nicht erreichbar.",
				"aus": "Liedtexte sind aus (Einstellungen › Klang)." }.get(
				_state, "")
		draw_string(UzTheme.font("medium"), Vector2(4, size.y * 0.4), tr(str(msg)), HORIZONTAL_ALIGNMENT_LEFT, w, 22, UzTheme.col("faint"))
		return
	_messen()
	_gezeichnet = _scroll
	var synced := not (_data.get("synced", []) as Array).is_empty()
	# Die laufende Zeile steht größer: Was darunter liegt, rückt um den Unterschied nach.
	var mehr := 0.0
	if synced and _idx >= 0 and _idx < _zeilen.size():
		mehr = font.get_multiline_string_size(_zeilen[_idx], HORIZONTAL_ALIGNMENT_LEFT, w, FS).y - (_oben[_idx + 1] - _oben[_idx] - GAP)
	# Oben blendet der Text erst aus, wenn er gerollt ist (am Anfang steht die erste Zeile ganz da).
	var oben_k := clampf(_scroll / 60.0, 0.0, 1.0)
	for i in _zeilen.size():
		var cur := synced and i == _idx
		var y := 40.0 + _oben[i] - _scroll + (mehr if synced and i > _idx else 0.0)
		var h := _oben[i + 1] - _oben[i] - GAP + (mehr if cur else 0.0)
		if y + h <= -40.0:
			continue
		if y >= size.y + 40.0:
			break
		var a := 1.0
		if synced:
			a = 1.0 if cur else (0.38 if i > _idx else 0.22)
		# Oben und unten weich ausblenden.
		a *= lerpf(1.0, clampf(y / 90.0, 0.0, 1.0), oben_k) * clampf((size.y - y) / 120.0, 0.0, 1.0)
		if a <= 0.004:
			continue
		var fs := FS if cur else FS_SMALL
		var col := UzTheme.col("text") if cur else UzTheme.col("muted")
		draw_multiline_string(font, Vector2(4, y + font.get_ascent(fs)), _zeilen[i], HORIZONTAL_ALIGNMENT_LEFT, w, fs, -1, Color(col, a))
	if not _zeilen.is_empty():
		draw_string(UzTheme.font("regular"), Vector2(4, size.y - 8), tr("Songtext: LRCLIB"), HORIZONTAL_ALIGNMENT_LEFT, w, UzTheme.size("cap"),
				UzTheme.col("faint", 0.6))

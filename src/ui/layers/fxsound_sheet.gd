extends "res://src/ui/layers/sheet.gd"
## FxSound aus Uzai bedienen (Einstellungen › Klang › FxSound, Guide › Lautstärke › FxSound): Klangverbesserung
## an und aus, Klangprofil wählen, FxSound still starten. Der Stand kommt von FxSound selbst (Mixer.tonwahl,
## src/core/fxsound.gd); jede Wahl geht als Befehl an das laufende FxSound, und das Blatt zeigt danach, was
## FxSound meldet – nicht, was Uzai sich wünscht. Die Tonausgabe wählt man in „Ton ausgeben über“.

const Main := preload("res://src/main.gd")
const FxSound := preload("res://src/core/fxsound.gd")
const WinRow := preload("res://src/ui/components/win_row.gd")

var main: Main
var _gelesen := false
var _busy := false


static func open_for(m: Main) -> Control:
	var s = load("res://src/ui/layers/fxsound_sheet.gd").new()
	s.main = m
	s.setup("FxSound", "Klang für alles, was der PC ausgibt", 720)
	m.open_layer(s)
	return s


func build() -> void:
	super()
	Mixer.tonwahl.changed.connect(_stand_neu)
	_lesen()


func _lesen() -> void:
	await Mixer.tonwahl.fx_lesen(true)
	if not is_inside_tree() or _closing:
		return
	_gelesen = true
	await refill()
	if is_inside_tree() and Nav.top_layer() == self and (Nav.focused() == null or not content.is_ancestor_of(Nav.focused())):
		var d := Nav.default_in(content)
		if d:
			Nav.focus(d, true)


## FxSound hat einen neuen Stand gemeldet (auch von außen umgestellt): neu zeichnen, die Auswahl bleibt.
func _stand_neu() -> void:
	if _gelesen and not _busy and is_inside_tree() and not _closing:
		refill()


func fill() -> void:
	if not _gelesen:
		add_label("Einen Moment …", "s", "faint")
		return
	var fx: Dictionary = Mixer.tonwahl.fx
	if not bool(fx.da):
		add_label("FxSound ist auf diesem PC nicht installiert.", "m", "muted")
		add_label("Kostenlos von fxsound.com. Ist es installiert, lässt es sich hier bedienen.", "s", "faint")
		return
	if not bool(fx.laeuft):
		add_label("FxSound läuft nicht.", "m", "muted")
		var st = SettingRow.new()
		st.setup("action", "FxSound starten", "Still im Hintergrund, ohne Fenster.")
		st.icon_name = "play"
		st.set_meta("uz_key", "fx:start")
		st.set_meta("uz_default", true)
		st.on_activate = _starten
		add_row(st)
		_auto_zeile()
		return
	if bool(fx.alt):
		add_label("Diese Fassung von FxSound nimmt noch keine Befehle an.", "m", "muted")
		add_label("In FxSound auf 1.2.11 oder neuer aktualisieren.", "s", "faint")
		return
	if not bool(fx.bedienbar):
		add_label("FxSound antwortet gerade nicht.", "m", "muted")
		var neu = SettingRow.new()
		neu.setup("action", "Erneut versuchen", "")
		neu.icon_name = "refresh"
		neu.set_meta("uz_default", true)
		neu.on_activate = _lesen
		add_row(neu)
		return
	var an = SettingRow.new()
	an.setup("toggle", "Klangverbesserung", "", bool(fx.an))
	an.icon_name = "pulse"
	an.set_meta("uz_key", "fx:an")
	an.set_meta("uz_default", true)
	an.changed.connect(func(v: Variant) -> void: _setzen({ "power": bool(v) }))
	add_row(an)
	var aus = SettingRow.new()
	aus.setup("action", "Tonausgabe", "")
	aus.icon_name = "speaker"
	aus.value_text = str(fx.geraet)
	aus.set_meta("uz_key", "fx:aus")
	aus.on_activate = func() -> void: main.open_audio_devices()
	add_row(aus)
	add_gap()
	add_label("Klangprofil")
	if not bool(fx.an):
		add_label("Profile gelten, sobald die Klangverbesserung an ist.", "s", "faint")
	else:
		for p in fx.profile:
			var name := str(p)
			var gewaehlt := name == str(fx.profil)
			var r = WinRow.new()
			r.setup(name, "", "music")
			r.on = gewaehlt
			r.state = tr("Aktiv") if gewaehlt else ""
			r.min_h = 62
			r.set_meta("uz_key", "fx:p:" + name)
			r.set_meta("uz_hint_a", "—" if gewaehlt else "Wählen")
			r.activated.connect(_profil.bind(name))
			add_row(r)
	add_gap()
	_auto_zeile()


## „Mit Uzai starten“: FxSound still mitstarten, wenn es beim Start von Uzai nicht läuft.
func _auto_zeile() -> void:
	var auto = SettingRow.new()
	auto.setup("toggle", "Mit Uzai starten", "FxSound startet still mit, wenn es nicht läuft.", bool(Config.get_value("ton.fxsound_start", false)))
	auto.set_meta("uz_key", "fx:auto")
	auto.changed.connect(func(v: Variant) -> void: Config.set_value("ton.fxsound_start", bool(v)))
	add_row(auto)


func _profil(name: String) -> void:
	if name != str(Mixer.tonwahl.fx.profil):
		_setzen({ "preset": name })


## Einen Befehl an FxSound schicken; danach steht da, was FxSound meldet.
func _setzen(was: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	var ok: bool = await Mixer.tonwahl.fx_setzen(was)
	_busy = false
	if not is_inside_tree() or _closing:
		return
	if ok:
		Sfx.play("select")
	else:
		Toasts.show_toast("FxSound hat nicht reagiert", "Läuft FxSound noch? Erneut versuchen.", "warning")
	refill()


func _starten() -> void:
	if _busy:
		return
	_busy = true
	Toasts.show_toast("FxSound startet", "Still im Hintergrund.", "pulse", { "ms": 2400, "quiet": true })
	var ok: bool = await Mixer.tonwahl.fx_starten()
	_busy = false
	if not is_inside_tree() or _closing:
		return
	if not ok:
		Toasts.show_toast("FxSound ist nicht gestartet", "FxSound einmal von Hand öffnen.", "warning")
	refill()

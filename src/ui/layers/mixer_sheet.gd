extends "res://src/ui/layers/sheet.gd"
## Lautstärkemixer (Guide → System → „Lautstärke“): oben das Mikrofon, dann die Gesamtlautstärke
## und je Programm, das gerade Ton ausgibt, eine Zeile (Mixer.rows) – links/rechts leiser bzw.
## lauter, A stumm. Alle REFRESH_S Sekunden sieht er nach, ob Programme dazugekommen oder
## verstummt sind; neue Zeilen blenden ein, verstummte gehen, sobald sie nicht gewählt sind.

const MixRow := preload("res://src/ui/components/mix_row.gd")
const Main := preload("res://src/main.gd")
const FxSound := preload("res://src/core/fxsound.gd")
const FxSheet := preload("res://src/ui/layers/fxsound_sheet.gd")
const REFRESH_S := 2.0
## So lange nach einem Druck gilt der eigene Stand (der Helfer antwortet kurz danach).
const TOUCH_MS := 1500

var _rows := {}                 ## Zeilen-ID -> MixRow
var _data := {}                 ## Zeilen-ID -> Zeile aus Mixer.rows
var _touched := {}              ## Zeilen-ID -> letzter Druck (ms)
var _gone := {}                 ## Zeilen-ID -> gibt keinen Ton mehr aus
var _mic: Control
var _master_box: VBoxContainer
var _apps_box: VBoxContainer
var _apps_head: Label
var _note: Label
var _loading := false
var _opened_ms := 0
var main: Main
var _aus: Control                ## Zeile „Tonausgabe“ (worüber der Ton geht)
var _fx: Control                 ## Zeile „FxSound“ (nur wenn es installiert ist)


static func open_for(m: Main) -> void:
	var s = load("res://src/ui/layers/mixer_sheet.gd").new()
	s.main = m
	s.setup("Lautstärke", "Was gerade Ton ausgibt", 760)
	m.open_layer(s)


## Welches Mikrofon, und ob Discord mitgeschaltet wird.
static func _mic_line() -> String:
	return Mixer.mic_text(Mixer.mic_known or Config.is_windows() or Library.demo, Voice.ready_(), Mixer.mic_name)


func build() -> void:
	set_meta("uz_hints", [["lr", "Leiser / lauter"]])
	super()
	Mixer.row_changed.connect(_on_row_changed)
	Mixer.mic_changed.connect(_on_mic)
	Mixer.tonwahl.changed.connect(_ausgabe_neu)
	_ausgabe_lesen()
	var t := Timer.new()
	t.wait_time = REFRESH_S
	t.timeout.connect(_load)
	add_child(t)
	t.start()
	_load()


## Oben die Gesamtlautstärke (sobald der Helfer sie nennt), dann das Mikrofon, dann die Programme.
func fill() -> void:
	_opened_ms = Time.get_ticks_msec()
	_master_box = U.vbox(6)
	_master_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row(_master_box)
	_mic = SettingRow.new()
	_mic.setup("toggle", "Mikrofon", "", not Mixer.mic_muted)
	_mic.icon_name = "mic_off" if Mixer.mic_muted else "mic"
	_mic.subtitle = _mic_line()
	_mic.set_meta("uz_key", "mix:mic")
	_mic.changed.connect(func(v: Variant) -> void:
		await Mixer.set_mic(not bool(v))
		# Ging es nicht (kein Mikrofon), springt der Schalter zurück.
		_on_mic(Mixer.mic_muted)
	)
	add_row(_mic)
	_ausgabe_zeilen()
	add_gap(10)
	_apps_head = add_label("Programme mit Ton")
	_apps_head.visible = false
	_apps_box = U.vbox(6)
	_apps_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row(_apps_box)
	_note = add_label("Einen Moment …", "s", "faint")


## Worüber der Ton geht und – wenn installiert – FxSound, ohne Uzai zu verlassen (Mixer.tonwahl): A öffnet die
## Auswahl der Tonausgabe bzw. das Blatt von FxSound (an/aus, Klangprofil).
func _ausgabe_zeilen() -> void:
	if not (Config.is_windows() or Library.demo) or main == null:
		return
	_aus = SettingRow.new()
	_aus.setup("action", "Tonausgabe", "")
	_aus.icon_name = "speaker"
	_aus.set_meta("uz_key", "mix:aus")
	_aus.on_activate = func() -> void: main.open_audio_devices()
	add_row(_aus)
	if bool(Config.get_value("ton.fxsound_da", false)) or Library.demo:
		_fx = SettingRow.new()
		_fx.setup("action", "FxSound", "")
		_fx.icon_name = "pulse"
		_fx.value_text = FxSound.kurz(Mixer.tonwahl.fx)
		_fx.set_meta("uz_key", "mix:fx")
		_fx.on_activate = func() -> void: FxSheet.open_for(main)
		add_row(_fx)


## Namen des Geräts, über das der Ton geht, und den Stand von FxSound nachlesen (einmal beim Öffnen).
func _ausgabe_lesen() -> void:
	if not (Config.is_windows() or Library.demo):
		return
	var liste: Dictionary = await Mixer.tonwahl.geraete_lesen()
	if bool(Config.get_value("ton.fxsound_da", false)) or Library.demo:
		await Mixer.tonwahl.fx_lesen()
	if not is_inside_tree() or _closing:
		return
	for d in liste.devices:
		if str(d.id) == str(liste.current) and is_instance_valid(_aus):
			_aus.set_value_text(str(d.name))
	_ausgabe_neu()


func _ausgabe_neu() -> void:
	if is_instance_valid(_fx):
		_fx.set_value_text(FxSound.kurz(Mixer.tonwahl.fx))
	var fx: Dictionary = Mixer.tonwahl.fx
	if is_instance_valid(_aus) and bool(fx.bedienbar) and str(fx.geraet) != "":
		_aus.set_value_text(str(fx.geraet))


func _on_mic(on: bool) -> void:
	if not is_instance_valid(_mic):
		return
	_mic.icon_name = "mic_off" if on else "mic"
	_mic.subtitle = _mic_line()
	if bool(_mic.value) == on:
		_mic.value = not on
		_mic._refresh()


func _load() -> void:
	if _loading or _closing:
		return
	_loading = true
	var snap: Dictionary = await Mixer.snapshot()
	_loading = false
	if not is_inside_tree() or _closing:
		return
	if not bool(snap.get("ok", false)):
		if _rows.is_empty():
			var err := str(snap.get("error", ""))
			_note.text = err if err != "" else "Gerade gibt nichts Ton aus."
			_note.visible = true
		return
	_merge(snap.get("rows", []))


## Neue Zeilen an ihrer Stelle einfügen, bekannte auffrischen, verstummte entfernen.
func _merge(list: Array) -> void:
	var seen := {}
	var idx := 0
	for r in list:
		var id := str(r.id)
		seen[id] = true
		_data[id] = r
		_gone.erase(id)
		var row: Control = _rows.get(id)
		if row == null:
			row = _make(r)
			_rows[id] = row
			var box := _master_box if id == "master" else _apps_box
			box.add_child(row)
			if id != "master":
				box.move_child(row, mini(idx, box.get_child_count() - 1))
			row.modulate.a = 0.0
			U.tw(row, "uz_in").tween_property(row, "modulate:a", 1.0, U.T_BASE)
			# Gleich nach dem Öffnen: die Gesamtlautstärke wählen (das Mikrofon war nur zuerst da).
			if id == "master" and Nav.focused() == _mic and Time.get_ticks_msec() - _opened_ms < 1500:
				Nav.focus(row, true)
		elif Time.get_ticks_msec() - int(_touched.get(id, 0)) > TOUCH_MS and not Mixer.pending(id):
			row.show_level(int(r.level), bool(r.mute))
		if id != "master":
			idx += 1
	for id in _rows.keys():
		if not seen.has(id):
			_gone[id] = true
	_drop_gone()
	var apps := _rows.keys().filter(func(k: String) -> bool: return k != "master").size()
	_apps_head.visible = apps > 0
	_note.visible = apps == 0
	_note.text = "Gerade gibt kein Programm Ton aus."


func _make(r: Dictionary) -> Control:
	var id := str(r.id)
	var row = MixRow.new()
	row.setup("slider", str(r.title), "", clampi(int(r.level), 0, 100) / 100.0)
	row.icon_name = str(r.icon)
	row.subtitle = str(r.sub)
	row.muted = bool(r.mute)
	row.set_meta("uz_key", "mix:" + id)
	if id == "master":
		row.set_meta("uz_default", true)
	row.changed.connect(func(v: Variant) -> void:
		_touched[id] = Time.get_ticks_msec()
		Mixer.set_level(_data.get(id, r), roundi(float(v) * 100.0))
	)
	row.mute_toggled.connect(func(on: bool) -> void:
		_touched[id] = Time.get_ticks_msec()
		Mixer.set_mute(_data.get(id, r), on)
	)
	return row


## Verstummte Zeilen gehen weich – die gewählte erst, wenn die Auswahl weiterzieht.
func _drop_gone() -> void:
	for id in _gone.keys():
		var row: Control = _rows.get(id)
		if row == null:
			_gone.erase(id)
			continue
		if row.has_focus():
			continue
		_rows.erase(id)
		_gone.erase(id)
		var tw := U.tw(row, "uz_in")
		tw.tween_property(row, "modulate:a", 0.0, U.T_FAST)
		tw.tween_callback(row.queue_free)


func _on_row_changed(id: String, level: int, mute: bool) -> void:
	var row: Control = _rows.get(id)
	if row == null:
		return
	if level < 0:
		_gone[id] = true
		_drop_gone()
		return
	if not Mixer.pending(id):
		row.show_level(level, mute)

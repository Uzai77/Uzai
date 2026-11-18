extends "res://src/ui/components/setting_row.gd"
## Eine Zeile im Lautstärkemixer (mixer_sheet.gd): links/rechts ändern den Pegel in Schritten,
## A schaltet stumm. Stumm steht rechts „Stumm“ und die Schiene wird leise; lauter (rechts) hebt
## Stumm zuerst auf – wie die Lautstärketasten –, der Pegel bleibt, wo er war.

signal mute_toggled(on: bool)

var muted := false:
	set(v):
		muted = v
		track_dim = v
		tone = "warn" if v else ""
		if _ready_done:
			set_meta("uz_hint_a", _hint())
			_refresh()
			Nav.focus_moved.emit(Nav.focused())


func _init() -> void:
	kind = "slider"
	min_v = 0.0
	max_v = 1.0
	step = Mixer.STEP / 100.0


func _full_text() -> String:
	return "Stumm" if muted else super()


func _hint() -> String:
	return "Ton an" if muted else "Stumm"


func activate_sound() -> String:
	return "toggle_on" if muted else "toggle_off"


func activate() -> void:
	muted = not muted
	mute_toggled.emit(muted)


func nav_lr(dir: int) -> bool:
	if dir > 0 and muted:
		muted = false
		Sfx.play("toggle_on")
		mute_toggled.emit(false)
		return true
	return super(dir)


## Stand vom Helfer übernehmen (Pegel 0..100), ohne Signal.
func show_level(level: int, mute: bool) -> void:
	value = clampi(level, 0, 100) / 100.0
	muted = mute
	if _ready_done:
		_refresh()

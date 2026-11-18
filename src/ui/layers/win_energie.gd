extends "res://src/ui/layers/sheet.gd"
## Energie mit dem Controller (Einstellungen → System → Windows → Energie): Energiesparplan (wie im
## Guide unter Leistung, hier aber dauerhaft), dazu Bildschirm aus, Schlafen und – wenn Windows ihn
## anbietet – Ruhezustand nach … am Netz und, bei einem Akku, im Akkubetrieb. Werte nur aus der
## festen Liste (WinEinst.POWER_MINUTES); links/rechts wählt, angewendet wird nach einer kurzen Pause
## (über powercfg, ohne Adminrechte). Sperren und Abmelden gibt es hier bewusst nicht.

const WinEinst := preload("res://src/core/win_einst.gd")
const PerfLive := preload("res://src/core/perf_live.gd")
const Fremd := preload("res://src/core/fremd.gd")
const SELF := "res://src/ui/layers/win_energie.gd"
const SETTLE_S := 0.7              ## so lange nach dem letzten Druck, dann zu Windows

const Main := preload("res://src/main.gd")
var main: Main
var _p := {}
var _plans := {}
var _loaded := false
var _due := {}                     ## Schlüssel → Callable, die nach SETTLE_S läuft
var _timer: Timer
static var _demo_state := {}

const WHAT := [["monitor", "Bildschirm aus nach", "monitor", "Spart Strom und schont den Fernseher"],
	["sleep", "Schlafen nach", "moon", "Energiesparmodus – das Spiel bleibt offen"],
	["hibernate", "Ruhezustand nach", "power", "Schaltet ganz aus, alles bleibt offen – startet langsamer"]]


static func open_for(m: Main) -> Control:
	var s = load(SELF).new()
	s.setup("Energie", "Wann Windows Strom spart", 820)
	m.open_layer(s)
	return s


func build() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = SETTLE_S
	_timer.timeout.connect(_apply_due)
	add_child(_timer)
	super()
	_load()


func fill() -> void:
	if not _loaded:
		add_label("Einen Moment …", "s", "faint")
		return
	if not bool(_p.ok):
		add_label("Windows hat die Energie-Einstellungen gerade nicht verraten. Gleich noch einmal öffnen.", "s", "muted")
		return
	if bool(_plans.get("ok", false)) and not (_plans.plans as Array).is_empty():
		add_label("Energiesparplan")
		var plan = SettingRow.new()
		var opts: Array = []
		for p in _plans.plans:
			opts.append([str(p.id), str(PerfLive.plan_name(str(p.id), str(p.name)).text)])
		plan.setup("choice" if bool(_plans.can_set) else "info", "Energiesparplan", "", str(_plans.active))
		plan.options = opts
		plan.icon_name = "bolt"
		plan.subtitle = "Gilt, bis du ihn wieder umstellst"
		if not bool(_plans.can_set):
			for o in opts:
				if o[0] == str(_plans.active):
					plan.value_text = str(o[1])
		plan.set_meta("uz_key", "en:plan")
		plan.changed.connect(func(v: Variant) -> void: _later("plan", _set_plan.bind(str(v))))
		add_row(plan)
		add_gap()
	for src in (["ac", "dc"] if bool(_p.battery) else ["ac"]):
		if bool(_p.battery):
			add_label("Am Netz" if src == "ac" else "Im Akkubetrieb")
		else:
			add_label("Zeiten")
		for w in WHAT:
			if str(w[0]) == "hibernate" and not bool(_p.hibernate_ok):
				continue
			var cur := int((_p[src] as Dictionary).get(str(w[0]), -1))
			if cur < 0:
				continue
			var r = SettingRow.new()
			r.setup("choice" if bool(_p.can_set) else "info", str(w[1]), "", cur)
			r.options = WinEinst.power_options(cur)
			if not bool(_p.can_set):
				r.value_text = WinEinst.minutes_text(cur)
			r.icon_name = str(w[2])
			r.subtitle = str(w[3])
			r.set_meta("uz_key", "en:%s:%s" % [str(w[0]), src])
			var what := str(w[0])
			var s2 := str(src)
			r.changed.connect(func(v: Variant) -> void: _later(what + s2, _set_time.bind(what, s2, int(v))))
			add_row(r)
		add_gap()
	if not bool(_p.can_set):
		add_label("Eine Richtlinie dieses PCs sperrt diese Werte. Freigeben nur mit Administratorrechten in Windows.", "s", "faint")
	else:
		add_label("Ändert die Werte direkt in Windows.", "s", "faint")


func _demo() -> bool:
	return Library.demo and not Config.is_windows()


func _load() -> void:
	if _demo():
		if _demo_state.is_empty():
			_demo_state = WinEinst.DEMO_POWER.duplicate(true)
		_p = WinEinst.parse_power(_demo_state)
	elif Helper.available:
		var r := await Helper.run("power-times", {}, 10.0)
		var res: Variant = r.get("result")
		var js: Variant = Fremd.json_roh(str((res as Dictionary).get("json", ""))) if bool(r.get("ok", false)) and res is Dictionary else null
		_p = WinEinst.parse_power(js)
	else:
		_p = WinEinst.parse_power(null)
	_plans = await PerfLive.load_plans()
	if not is_inside_tree() or _closing:
		return
	_loaded = true
	refill()
	await get_tree().process_frame
	if is_inside_tree() and Nav.top_layer() == self and (Nav.focused() == null or not content.is_ancestor_of(Nav.focused())):
		var d := Nav.default_in(content)
		if d:
			Nav.focus(d, true)


## Schnell durchblättern startet nicht für jeden Schritt powercfg: der letzte Wert gilt.
func _later(key: String, job: Callable) -> void:
	_due[key] = job
	_timer.start()


func _apply_due() -> void:
	var jobs := _due.values()
	_due.clear()
	for j in jobs:
		await (j as Callable).call()


## Vor Ablauf der Pause geschlossen (Wert gewählt, gleich B): Was noch aussteht, geht sofort zu Windows – früher
## ging die letzte Änderung dann still verloren. Ohne zu warten: Jeder Auftrag ist abgeschickt, bevor die Ebene geht.
func close() -> void:
	if not _closing and not _due.is_empty():
		if is_instance_valid(_timer):
			_timer.stop()
		var jobs := _due.values()
		_due.clear()
		for j in jobs:
			(j as Callable).call()
	super()


func _set_plan(id: String) -> void:
	if await PerfLive.set_plan(id):
		# Ein im Guide fürs Spiel umgestelltes Profil soll danach nicht über deine Wahl hinweg zurück.
		Config.set_value("system.power_restore", "")
		Toasts.show_toast("Energiesparplan umgestellt", "", "bolt", { "quiet": true, "ms": 2500 })
	elif is_inside_tree():
		Toasts.show_toast("Energiesparplan nicht umgestellt", "Windows hat es nicht zugelassen. Noch einmal versuchen oder in Windows unter Energie umstellen.",
				"warning")


func _set_time(what: String, src: String, minutes: int) -> void:
	var a := WinEinst.power_args(what, src, minutes)
	if a.is_empty():
		return
	var code := "ok"
	if _demo():
		(_demo_state[src] as Dictionary)[what] = minutes * 60
	else:
		code = WinEinst.code_of(await Helper.run("power-time-set", a, 10.0))
	if not is_inside_tree():
		return
	if code != "ok":
		var s := WinEinst.status(code)
		Toasts.show_toast(str(s[0]), str(s[1]), "warning")
		_load()

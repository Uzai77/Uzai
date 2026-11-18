extends Control
## Am Jackenständer die Figur wechseln – gleich im Zimmer, in einem Schritt: Die Kamera tritt vor deine
## Figur (bewohner.gd vor_figur), unten steht eine kleine Leiste mit dem Namen. ←/→ zieht die nächste
## Figur an (sofort an dir zu sehen), A behält sie, B nimmt sie zurück, Y öffnet den ganzen
## Figur-Editor (Haustier, Zufall, Emotes). Was erst durchs Spielen frei wird, lässt sich anprobieren;
## behalten geht erst, wenn der Meilenstein erreicht ist (die Leiste sagt, wie).

const D := preload("res://src/room/figur/figur_daten.gd")
const M := preload("res://src/room/figur/meilensteine.gd")
const U := preload("res://src/ui/u.gd")
const Bewohner := preload("res://src/room/figur/bewohner.gd")

var bewohner: Bewohner
var offen := false
var _vorher := {}                ## Figur beim Öffnen (B nimmt die Probe zurück)
var _sel := 0
var _panel: PanelContainer
var _name: Label
var _zahl: Label
var _sperre: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UzTheme.lift(UzTheme.box(Color(UzTheme.col("surface"), 0.92), 34), 2))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var m := U.margin(34, 16, 34, 18)
	_panel.add_child(m)
	var v := U.vbox(2)
	m.add_child(v)
	var kopf := U.label(tr("Jackenständer").to_upper(), "cap", "muted", "bold")
	kopf.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(kopf)
	var reihe := U.hbox(22)
	reihe.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(reihe)
	reihe.add_child(U.label("‹", "xl", "muted", "bold"))
	_name = U.label("", "xl", "text", "bold")
	_name.custom_minimum_size = Vector2(220, 0)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reihe.add_child(_name)
	reihe.add_child(U.label("›", "xl", "muted", "bold"))
	_zahl = U.label("", "xs", "muted")
	_zahl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_zahl)
	_sperre = U.label("", "xs", "accent")
	_sperre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_sperre)
	visible = false
	modulate.a = 0.0


static func personen() -> Array:
	return D.FIGUR_FELDER[0][3]


## Frei zu tragen? (Meilensteine, meilensteine.gd)
static func frei(id: String, erreichte: Array) -> bool:
	return M.ist_frei("person:" + id, erreichte)


func oeffnen() -> void:
	var f: Dictionary = (bewohner.daten as Dictionary).get("figur", {})
	_vorher = M.nur_freies(D.pruefe_figur(f), D.FIGUR_FELDER, bewohner.erreichte)
	_sel = maxi(0, personen().map(func(p: Array) -> String: return str(p[0])).find(str(_vorher.get("person", ""))))
	offen = true
	visible = true
	bewohner.vor_figur(true)
	_zeigen()
	await get_tree().process_frame
	if not offen:
		return
	_panel.reset_size()
	_panel.position = Vector2(-_panel.size.x * 0.5, -_panel.size.y - 132)
	var tw := U.tw(self, "uz_garderobe", Tween.TRANS_QUART)
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, U.T_BASE)
	tw.tween_property(_panel, "position:y", -_panel.size.y - 132, U.T_MOVE).from(-_panel.size.y - 108)
	bewohner.zimmer._hinweise_auffrischen()


func schliessen() -> void:
	offen = false
	bewohner.vor_figur(false)
	var tw := U.tw(self, "uz_garderobe", Tween.TRANS_CUBIC, Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, U.T_FAST)
	tw.tween_callback(func() -> void: visible = false)
	bewohner.zimmer._hinweise_auffrischen()


## Die nächste (d = ±1) Figur anprobieren: gleich an dir zu sehen.
func schritt(d: int) -> void:
	var p := personen()
	_sel = posmod(_sel + d, p.size())
	Sfx.play("move")
	bewohner.avatar.bauen({ "person": str(p[_sel][0]) })
	_zeigen()


func taste(cmd: String) -> bool:
	match cmd:
		"left", "right", "lb", "rb":
			schritt(-1 if cmd in ["left", "lb"] else 1)
		"a":
			var id := str(personen()[_sel][0])
			if not frei(id, bewohner.erreichte):
				Sfx.play("error")
				return true
			bewohner.daten["figur"] = M.nur_freies({ "person": id }, D.FIGUR_FELDER, bewohner.erreichte)
			bewohner.zimmer.speichern()
			bewohner.neu_laden()
			bewohner.avatar.emote("jubeln")
			Sfx.play("select")
			schliessen()
		"b":
			Sfx.play("back")
			bewohner.avatar.bauen(_vorher)
			schliessen()
		"y":
			bewohner.avatar.bauen(_vorher)
			offen = false
			visible = false
			modulate.a = 0.0
			bewohner.zimmer.figur_editor("figur").tree_exited.connect(func() -> void:
				if is_instance_valid(bewohner):
					bewohner.vor_figur(false)
					bewohner.zimmer._hinweise_auffrischen(), CONNECT_ONE_SHOT)
			Sfx.play("open")
		"guide":
			return false
	return true


func hinweise() -> Array:
	var id := str(personen()[_sel][0])
	return [["a", "Anziehen" if frei(id, bewohner.erreichte) else "Noch gesperrt"], ["y", "Figur-Editor"], ["b", "Abbrechen"]]


func _zeigen() -> void:
	var p: Array = personen()[_sel]
	_name.text = tr(str(p[1]))
	_zahl.text = "%d / %d" % [_sel + 1, personen().size()]
	var wie := M.bedingung("person:" + str(p[0]), bewohner.erreichte)
	_sperre.text = tr("Noch gesperrt: %s") % tr(wie) if wie != "" else ""
	_sperre.visible = wie != ""
	_panel.reset_size()
	_panel.position.x = -_panel.size.x * 0.5
	bewohner.zimmer._hinweise_auffrischen()

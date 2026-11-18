extends RefCounted
## Eine Reihe von Apps für das Menü „langes A“ (quellen_ordnung.gd): die Symbole der Apps in der
## Leiste oben bzw. die Kacheln im Ordner „Meine Apps“ (app_ordner.gd). Verschieben, Ausblenden,
## Ausgeblendetes zurückholen, bei eigenen Apps Entfernen – gemerkt in apps.order und apps.hidden
## (src/core/leiste_oben.gd), dieselben Schlüssel wie früher in der Reihe des Reiters „Apps“.

const LeisteOben := preload("res://src/core/leiste_oben.gd")
const AppsExtern := preload("res://src/core/apps_extern.gd")

## Für quellen_ordnung.gd: wo Reihenfolge und Ausgeblendetes stehen, wie die Einträge heißen.
var order_key := "apps.order"
var hidden_key := "apps.hidden"
var key_prefix := "tab:"

## Offen getypt (Node statt Main): Tests geben sich selbst als main aus (logic_leiste).
var main: Node
var _ids: Callable           ## → Array: IDs der Apps in dieser Reihe, in ihrer Reihenfolge
var _box: Callable           ## → Control: der Behälter mit den Einträgen (zum Verschieben)


func _init(m: Node, ids: Callable, box: Callable, prefix: String) -> void:
	main = m
	_ids = ids
	_box = box
	key_prefix = prefix


## Die Apps dieser Reihe: [{ id, label }].
func subtabs() -> Array:
	var by := {}
	for t in LeisteOben.all_apps():
		by[str(t.id)] = t
	var out: Array = []
	for id in _ids.call():
		if by.has(str(id)):
			out.append(by[str(id)])
	return out


## Alle Apps (für die Liste der ausgeblendeten).
func all_subtabs() -> Array:
	return LeisteOben.all_apps()


func chip_box() -> Control:
	return _box.call()


## Langes A (oder X) auf einer App.
func menu(app_id: String, label: String) -> void:
	load("res://src/ui/sections/quellen_ordnung.gd").menu(main, self, app_id, label)


## Zusätzlich im Menü: bei eigenen Apps „Entfernen“.
func menu_extra(app_id: String) -> Array:
	return [["remove", "Entfernen"]] if AppsExtern.is_ext_id(app_id) else []


func menu_pick(v: String, app_id: String, label: String) -> void:
	if v == "remove":
		LeisteOben.remove_app(app_id, label)


## Ausgeblendet oder zurückgeholt: die Leiste neu einteilen.
func quellen_changed() -> void:
	main.call("_rebuild")


## Verschoben: die Reihe hat sich schon selbst bewegt, nur die Reihenfolge der Bereiche nachziehen.
func order_changed(_ids_now: Array) -> void:
	main.call("apps_umgestellt")

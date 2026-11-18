extends RefCounted
## Die Leiste oben (main.gd _build): vorn die Bereiche als Wörter (Spiele · Shop · Freunde · Profil),
## daneben hinter einem feinen Trenner die Apps als Symbole – Musik, Videos, Filme, Streams, Browser, Zimmer
## und die eigenen Apps (Store-Apps und Programme, src/core/apps_extern.gd) mit ihrem echten
## Symbol – und ganz rechts das Zahnrad (Einstellungen). „+“ (add) gibt es in der Leiste nicht mehr;
## App hinzufügen steht unter Einstellungen › Spiele › Leiste oben.
## Hier steht nur die Logik ohne Oberfläche: welche Apps in welcher Reihenfolge, was bei zu wenig
## Platz in den Ordner „Meine Apps“ wandert (app_ordner.gd), wohin alte Ziele (goto("apps"),
## „media“) führen und wie eine eigene App entfernt wird.
##
## Gemerkt wird wie bisher: apps.order (Reihenfolge, langes A → Verschieben), apps.hidden
## (Ausgeblendetes, langes A → Ausblenden, zurück im selben Menü oder unter Einstellungen → Leiste
## oben), apps.last (zuletzt benutzte App: Ziel alter Sprünge auf „Apps“), apps.extern (eigene Apps).
## „apps“ in theme.sections/hidden_sections steht für die ganze Gruppe (ausgeblendet: keine Symbole).
## Tests: tests/logic_leiste.gd.

const AppsExtern := preload("res://src/core/apps_extern.gd")
const Q := preload("res://src/ui/sections/quellen_ordnung.gd")
const BrowserDaten := preload("res://src/core/browser_daten.gd")

## Eingebaute Apps in ihrer gewohnten Reihenfolge (neue kommen hier dazu), Namen und Symbole.
const KIDS := ["music", "videos", "movies", "streams", "browser", "room"]
const NAMES := { "music": "Musik", "videos": "Videos", "movies": "Filme", "streams": "Streams", "browser": "Browser", "room": "Zimmer" }
const ICONS := { "music": "music", "videos": "video", "movies": "film", "streams": "live", "browser": "browser", "room": "room" }
## Kennung des Ordners „Meine Apps“ (auch der Bereich, app_ordner.gd) und des „+“.
const FOLDER := "apps"
const ADD := "+"


## Alle Apps, die es gerade gibt (Filme nur eingeschaltet, Zimmer nicht im sicheren Modus, der Browser
## nur unter Windows bzw. im Vorführmodus und nicht im Kinderprofil, eigene nur, wo sie erlaubt sind):
## [{ id, label, ext? }].
static func all_apps() -> Array:
	var out: Array = []
	for k in KIDS:
		if k == "movies" and not Movies.enabled():
			continue
		if k == "room" and Config.safe_mode:
			continue
		if k == "browser" and not BrowserDaten.verfuegbar():
			continue
		out.append({ "id": k, "label": NAMES[k] })
	if extern_allowed():
		for e in AppsExtern.entries():
			out.append({ "id": str(e.id), "label": str(e.name), "ext": true })
	return out


## Eigene Apps gibt es nur außerhalb des sicheren Modus und nicht im Kinderprofil.
static func extern_allowed() -> bool:
	return not Config.safe_mode and not Config.is_kid()


## Ist das eine App (eingebaut oder eigene)?
static func is_app_id(app_id: String) -> bool:
	return app_id in KIDS or AppsExtern.is_ext_id(app_id)


## Die Apps, wie sie in der Leiste stehen: eigene Reihenfolge, ohne ausgeblendete (mindestens eine
## bleibt). Ist die ganze Gruppe ausgeblendet („apps“ in theme.hidden_sections): keine.
static func shown(apps: Array, order: Array, hidden: Array, group_hidden := false) -> Array:
	if group_hidden or apps.is_empty():
		return []
	return Q.arrange(apps, order, hidden)


## Wie die Gruppe in die Leiste passt. apps: die gezeigten Apps in ihrer Reihenfolge, add: „+“ da,
## slots: so viele Symbole passen für die ganze Gruppe (Ordner und „+“ mitgezählt; < 0 = genug Platz).
## Passt nicht alles, wandern zuerst die eigenen Apps in den Ordner, reicht das nicht, von hinten auch
## eingebaute – nie wird etwas abgeschnitten. Ergebnis: { bar: [IDs in der Leiste, mit FOLDER an
## seinem Platz], folder: [IDs im Ordner], add: bool }.
static func plan(apps: Array, add: bool, slots: int) -> Dictionary:
	var ids: Array = apps.map(func(t: Dictionary) -> String: return str(t.id))
	var extra := 1 if add else 0
	if slots < 0 or ids.size() + extra <= slots:
		return { "bar": ids, "folder": [], "add": add }
	var bar: Array = ids.filter(func(x: String) -> bool: return not AppsExtern.is_ext_id(x))
	var folder: Array = ids.filter(func(x: String) -> bool: return AppsExtern.is_ext_id(x))
	# Reicht der Platz auch dann nicht: eingebaute von hinten dazu (der Ordner selbst braucht einen Platz).
	while not bar.is_empty() and bar.size() + 1 + extra > slots:
		folder.push_front(bar.pop_back())
	if folder.is_empty():
		return { "bar": bar, "folder": [], "add": add }
	# Im Ordner in derselben Reihenfolge wie in apps.order.
	folder.sort_custom(func(a: String, b: String) -> bool: return ids.find(a) < ids.find(b))
	bar.append(FOLDER)
	return { "bar": bar, "folder": folder, "add": add }


## Wohin main.goto(sec, sub) führt: [Bereich, Unterbereich]. Alte Ziele „apps“ und „media“
## (Fernbedienung, frühere Fassungen): die genannte App, sonst die zuletzt benutzte, sonst die erste
## App der Leiste, sonst der Ordner. apps: alle Apps mit Bereich (Leiste und Ordner), bar: Leiste.
static func resolve_goto(sec_id: String, sub_id: String, apps: Array, bar: Array, last: String) -> Array:
	if sec_id != FOLDER and sec_id != "media":
		return [sec_id, sub_id]
	if sub_id in apps:
		return [sub_id, ""]
	if sec_id == FOLDER and bar.has(FOLDER) and sub_id == "":
		return [FOLDER, ""]
	if last in apps:
		return [last, ""]
	for a in bar:
		if a in apps:
			return [str(a), ""]
	if bar.has(FOLDER):
		return [FOLDER, ""]
	return [str(apps[0]) if not apps.is_empty() else "", ""]


## Eigene App entfernen: weg aus Leiste, Reihenfolge und Ausgeblendetem; kurz zurücknehmbar.
static func remove_app(app_id: String, label: String) -> bool:
	var e := AppsExtern.get_entry(app_id)
	if e.is_empty():
		return false
	var was_ok := AppsExtern.confirmed(e)
	if not AppsExtern.remove(app_id):
		return false
	Undo.offer("Entfernt", label, "trash", func() -> void:
		if bool(AppsExtern._add(e).get("ok", false)) and was_ok:
			AppsExtern.confirm(e))
	return true


## Anfangsbuchstabe einer eigenen App ohne Logo (Programme): groß, ein Zeichen.
static func monogram(name: String) -> String:
	for ch in name.strip_edges():
		if ch.to_upper() != ch.to_lower() or ch.is_valid_int():
			return ch.to_upper()
	return "•"

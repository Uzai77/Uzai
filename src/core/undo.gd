extends Node
## Rückgängig (Roadmap 95): Nach einer Änderung, die etwas wegnimmt – Spiel ausblenden oder aus
## Uzai entfernen, Ordner, Ansicht oder Emulator löschen, mehrere Spiele auf einmal ändern, eigene
## Bilder oder einen Link entfernen, Clip, Bildschirmfoto oder Sicherung löschen, den Verlauf
## leeren – steht einige Sekunden eine Mitteilung mit „Rückgängig“. View nimmt die Änderung genau
## zurück (wie „Öffnen“ bei jedem Pop-up, egal welche Ebene offen ist).
##
## Immer nur die jüngste: Eine neue Änderung macht die vorige endgültig. Dateien löscht Uzai erst,
## wenn die Zeit um ist oder Uzai beendet wird – bis dahin bleiben sie, wo sie sind, und sind nur
## ausgeblendet (hides). Gelöscht wird dann auf demselben Weg wie vorher (Aufnahmen in den
## Papierkorb von Windows, Sicherungen nur im Ordner der Sicherungen), nie über Verknüpfungen.
## Was sich nicht sauber zurücknehmen lässt (Abmelden, Deinstallieren, eine Anfrage ablehnen,
## Weiterschauen im Nuvio-Konto), bekommt hier nichts und bleibt bei der Rückfrage.
##
## Die Rückwege legt Undo selbst an (offer_games, offer_setting, offer_files): Ebenen wie die
## Spieloptionen sind oft schon zu, wenn View kommt, und ihre eigenen Funktionen gälten dann nicht
## mehr. Was eine Ebene danach auffrischen will (after), läuft nur, solange es sie noch gibt.

signal held_changed

const Backup := preload("res://src/core/backup.gd")
const MS := 8000
const TAG := "undo"

var gen := 0                ## zählt hoch, wenn sich ausgeblendete Dateien ändern (Listen neu bauen)
var _cur := {}              ## { n, undo, done, files }
var _n := 0


## Die Nummer der Änderung, die gerade zurückgenommen werden kann (0: keine).
func pending() -> int:
	return int(_cur.get("n", 0))


## Ist diese Datei gerade zum Löschen vorgemerkt? Dann zeigen Listen sie nicht mehr.
func hides(path: String) -> bool:
	return not _cur.is_empty() and (_cur.files as Array).has(path)


## Eine Änderung ist geschehen: Mitteilung mit „Rückgängig“. undo stellt den Stand davor her, done
## läuft, wenn die Zeit um ist (Dateien endgültig löschen); files sind bis dahin ausgeblendet.
## undo und done müssen an etwas gebunden sein, das bleibt (siehe offer_games & Co.).
func offer(title: String, sub: String, icon: String, undo: Callable, done := Callable(), files: Array = []) -> int:
	settle()
	_n += 1
	var n := _n
	_cur = { "n": n, "undo": undo, "done": done, "files": files.duplicate() }
	if not files.is_empty():
		_files_changed()
	Toasts.show_toast(title, sub, icon, { "ms": MS, "quiet": true, "sound": "select", "tag": TAG,
		"open": func() -> void: take(n), "open_text": "Rückgängig" })
	_expire(n)
	return n


func _expire(n: int) -> void:
	await get_tree().create_timer(MS / 1000.0 + 0.4).timeout
	if pending() == n:
		settle()


## Zurücknehmen (View auf der Mitteilung). n: nur diese Änderung (0: die jüngste).
func take(n := 0) -> bool:
	if _cur.is_empty() or (n > 0 and pending() != n):
		return false
	var c := _cur
	_cur = {}
	Toasts.dismiss(TAG)
	if not (c.files as Array).is_empty():
		_files_changed()
	var u: Callable = c.undo
	if not u.is_valid():
		Toasts.show_toast("Geht nicht mehr", "Das lässt sich jetzt nicht mehr zurücknehmen.", "warning", { "ms": 3000, "quiet": true })
		return false
	u.call()
	Toasts.show_toast("Rückgängig gemacht", "", "undo", { "ms": 2200, "quiet": true })
	return true


## Die vorgemerkte Änderung endgültig machen (neue Änderung, Zeit um, Uzai geht zu).
func settle(closing := false) -> void:
	if _cur.is_empty():
		return
	var c := _cur
	_cur = {}
	if not closing:
		Toasts.dismiss(TAG)
	var d: Callable = c.done
	if d.is_valid():
		d.call()
	if not (c.files as Array).is_empty() and not closing:
		_files_changed()


func _files_changed() -> void:
	gen += 1
	held_changed.emit()


# Uzai geht zu: was zum Löschen vorgemerkt ist, jetzt löschen (es war ja bestätigt).
func _exit_tree() -> void:
	settle(true)


# --- Fertige Rückwege --------------------------------------------------------------------------

## Spiele (und, wenn gemerkt, die Ordner) auf den Stand von Library.snapshot zurück.
func offer_games(title: String, sub: String, icon: String, snap: Dictionary, after := Callable()) -> int:
	return offer(title, sub, icon, func() -> void:
		Library.restore(snap)
		if after.is_valid():
			after.call()
	)


## Eine Einstellung auf ihren alten Wert zurück (old ist schon eine Kopie).
func offer_setting(title: String, sub: String, icon: String, key: String, old: Variant, after := Callable()) -> int:
	return offer(title, sub, icon, func() -> void:
		Config.set_value(key, old)
		if after.is_valid():
			after.call()
	)


## Mehrere Schritte zurück (calls): nur Aufrufe an Uzais Dienste wie Config.set_value.bind(…) oder
## Library.scan – die gibt es noch, wenn View kommt.
func offer_calls(title: String, sub: String, icon: String, calls: Array, after := Callable()) -> int:
	return offer(title, sub, icon, func() -> void:
		for c in calls:
			if (c as Callable).is_valid():
				(c as Callable).call()
		if after.is_valid():
			after.call()
	)


## Dateien löschen, aber erst, wenn die Zeit um ist. kind: "capture" (Clip/Bildschirmfoto, in den
## Papierkorb von Windows wie bisher) oder "backup" (Sicherung, nur im Ordner der Sicherungen).
## after läuft nach dem Ausblenden, nach dem Zurücknehmen und nach dem Löschen (Listen neu).
func offer_files(title: String, sub: String, icon: String, paths: Array, kind: String, after := Callable()) -> int:
	var n := offer(title, sub, icon, func() -> void:
		_refresh(kind, after)
	, func() -> void:
		var left := 0
		for p in paths:
			if not delete_file(str(p), kind):
				left += 1
		if left > 0:
			Toasts.show_toast("Löschen ging nicht", "Die Datei ist vielleicht gerade geöffnet." if left == 1 else "%d Dateien sind vielleicht gerade geöffnet." % left,
					"warning")
		_refresh(kind, after)
	, paths)
	_refresh(kind, after)
	return n


func _refresh(kind: String, after: Callable) -> void:
	if kind == "capture":
		Capture.changed.emit("files")
	if after.is_valid():
		after.call()


## Endgültig löschen – nur, was Uzai selbst angelegt hat und dort liegt, wo es hingehört.
func delete_file(path: String, kind: String) -> bool:
	match kind:
		"capture":
			return Capture.is_own_file(path) and Capture.remove(path)
		"backup":
			return Backup.remove(Config.data_dir, path)
	return false


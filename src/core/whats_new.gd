extends RefCounted
## „Was ist neu“ (Punkt 141): Nach einem Update zeigt Uzai einmal eine ruhige Karte mit den
## wichtigsten Neuerungen. Sie stehen in data/neu.json (mitgeliefert, Deutsch und Englisch je
## Punkt) – Uzai lädt dafür nie etwas aus dem Netz. Nie beim allerersten Start (dann ist alles neu),
## später jederzeit unter Einstellungen → System → „Was ist neu“. Reine Logik, testbar
## (tests/logic_anfragen.gd).
##
## data/neu.json: { "<Fassung>": [{ icon, de: [Titel, Satz], en: [Titel, Satz] }, …], … }

const Fremd := preload("res://src/core/fremd.gd")

const FILE := "res://data/neu.json"
## Höchstens so viele Punkte auf der Karte (über mehrere Fassungen hinweg die neuesten).
const MAX_ITEMS := 6


## Fassungen vergleichen („0.10.0“ ist neuer als „0.9.2“). 1: a neuer, -1: b neuer, 0: gleich.
static func compare(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0


## Soll die Karte jetzt von selbst kommen? seen: bis zu welcher Fassung schon gezeigt ("" = nie);
## first_run: allererster Start (Einrichtung läuft) – dann nicht, Uzai merkt sich nur die Fassung.
## Wer von einer Fassung vor dieser Karte kommt (seen leer, kein erster Start), sieht sie einmal.
static func due(seen: String, current: String, first_run: bool, entries: Dictionary) -> bool:
	if first_run:
		return false
	return not items(entries, seen, current).is_empty()


## Punkte aller Fassungen nach seen bis einschließlich current, die neueste Fassung zuerst.
## seen leer: nur die Punkte der aktuellen Fassung. [{ version, icon, title, text }] in der Sprache
## lang („en“, sonst Deutsch).
static func items(entries: Dictionary, seen: String, current: String, lang := "de") -> Array:
	var versions: Array = entries.keys().filter(func(v: String) -> bool:
		if compare(v, current) > 0:
			return false
		return compare(v, current) == 0 if seen == "" else compare(v, seen) > 0)
	versions.sort_custom(func(a: String, b: String) -> bool: return compare(a, b) > 0)
	var out: Array = []
	for v in versions:
		for it in entries[v]:
			if not (it is Dictionary):
				continue
			var t: Variant = it.get("en" if lang == "en" else "de", it.get("de", []))
			if not (t is Array) or (t as Array).size() < 2:
				continue
			out.append({ "version": str(v), "icon": str(it.get("icon", "spark")), "title": str(t[0]), "text": str(t[1]) })
	return out.slice(0, MAX_ITEMS)


## Die Datei lesen; kaputt oder fehlend: {} (dann gibt es einfach keine Karte).
static func load_entries(path := FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = Fremd.json_roh(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		return {}
	var out := {}
	for k in d:
		# Nur Fassungen („0.9.0“) mit einer Liste; alles andere überspringen.
		if d[k] is Array and str(k).replace(".", "").is_valid_int():
			out[str(k)] = d[k]
	return out

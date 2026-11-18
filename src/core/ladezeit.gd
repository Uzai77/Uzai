extends RefCounted
## Ladezeiten der Medien-Bereiche (Videos, Shorts, Filme, Streams) für logs/leistung.log: wie
## lange nach dem Öffnen der erste Inhalt stand und wann alles da war. Damit lassen sich echte
## Zahlen vom eigenen PC schicken („Videos · Startseite: erster Inhalt nach 40 ms (vorgebaut),
## vollständig nach 2300 ms“). Nur Zeiten und Namen der Bereiche – keine Adressen, keine Konten.
##
## main.goto ruft oeffnen() vor dem Aufbau; der Bereich meldet danach mit pruefen(), was er zeigt
## (lade_stand(): { inhalt, fertig, art }). Eine Zeile je Öffnen, geschrieben, sobald alles da ist
## (oder nach FRIST_MS mit „noch nicht vollständig“).

const FRIST_MS := 60000

static var _offen := {}          ## Bereich → { t0, sub, erst (ms oder -1), quelle, fertig }
static var schreiber: Callable   ## Proben: Zeilen abfangen statt ins Protokoll


## Bereich wird geöffnet (vor dem Aufbau). sub: Unterbereich (Anzeigename).
static func oeffnen(bereich: String, sub: String, now_ms := -1) -> void:
	_offen[bereich] = { "t0": now_ms if now_ms >= 0 else Time.get_ticks_msec(), "sub": sub, "erst": -1, "quelle": "", "fertig": false }


## Stand des Bereichs nach Aufbau oder Änderung. stand: { inhalt: bool, fertig: bool, quelle: String }.
## quelle: woher der erste Inhalt kam („vorgebaut“, „gemerkt“, „Netz“).
static func melden(bereich: String, stand: Dictionary, now_ms := -1) -> String:
	var o: Dictionary = _offen.get(bereich, {})
	if o.is_empty() or bool(o.fertig):
		return ""
	var now := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	var dt := now - int(o.t0)
	if bool(stand.get("inhalt", false)) and int(o.erst) < 0:
		o.erst = dt
		o.quelle = str(stand.get("quelle", ""))
	var zeile := ""
	if bool(stand.get("fertig", false)) and (int(o.erst) >= 0 or not bool(stand.get("inhalt", false))):
		zeile = text(bereich, str(o.sub), int(o.erst), dt, str(o.quelle))
	elif dt > FRIST_MS:
		zeile = text(bereich, str(o.sub), int(o.erst), -1, str(o.quelle))
	if zeile != "":
		o.fertig = true
		_offen.erase(bereich)
		_schreiben(zeile)
	return zeile


## Bereich (Node mit lade_stand(), gemeldet unter seinem Titel) nach seinem Stand fragen und melden.
static func pruefen(bereich: Node) -> void:
	if bereich == null or not bereich.has_method("lade_stand") or not _offen.has(str(bereich.get("title"))):
		return
	melden(str(bereich.get("title")), bereich.call("lade_stand"))


## Die Zeile fürs Protokoll. erst/ganz: ms, -1 = noch nicht.
static func text(bereich: String, sub: String, erst: int, ganz: int, quelle := "") -> String:
	var name := bereich if sub == "" else "%s · %s" % [bereich, sub]
	var a := "erster Inhalt nach %d ms%s" % [erst, " (%s)" % quelle if quelle != "" else ""] if erst >= 0 else "kein Inhalt"
	var b := "vollständig nach %d ms" % ganz if ganz >= 0 else "nach %d s noch nicht vollständig" % (FRIST_MS / 1000)
	return "Laden %s: %s, %s" % [name, a, b]


static func _schreiben(zeile: String) -> void:
	if schreiber.is_valid():
		schreiber.call(zeile)
		return
	var ml := Engine.get_main_loop()
	var media: Node = (ml as SceneTree).root.get_node_or_null("Media") if ml is SceneTree else null
	if media:
		media.call("log_line", "leistung", zeile)

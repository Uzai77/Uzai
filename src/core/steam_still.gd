extends RefCounted
## Steam's own notifications (the pop-ups at the screen edge: achievements, friends online, downloads)
## stay hidden while Uzai is running, since Uzai shows achievements, messages and friends itself. They
## come back as soon as Uzai is no longer running.
##
## Steam has no switch for this that could be set from outside and only for that period. So the
## Windows helper makes Steam's notification windows invisible (UzSteamStill in
## helper/uzai-helper.ps1: empty window region) and restores them as soon as Uzai exits, even after
## a crash, because the helper exits along with it. Nothing changes in Steam's files or settings.
##
## Limits: what Steam's overlay draws inside a game is not a window, so that pop-up remains (it can
## only be turned off in Steam itself, and then permanently). Not yet tested on Windows; what the
## helper saw is in logs/helper.log ("steam-still: …").

const Fremd := preload("res://src/core/fremd.gd")

const KEY := "notify.steam_still"
const NACHSEHEN_S := 300.0

static var _runde := 0
static var _zuletzt := ""


## Einmal beim Start: jetzt anwenden, und nach jedem (Neu-)Start des Helfers wieder.
static func beim_start() -> void:
	if not Config.is_windows() or Library.demo:
		return
	Helper.helper_ready.connect(func() -> void: anwenden())
	if Helper.available:
		anwenden()


## Die Einstellung an den Helfer geben; solange sie an ist, alle fünf Minuten nachsehen und ins
## Protokoll schreiben, wenn sich etwas getan hat.
static func anwenden() -> void:
	if not Config.is_windows() or Library.demo or not Helper.available:
		return
	_runde += 1
	var runde := _runde
	var an := bool(Config.get_value(KEY, true))
	_melden(await Helper.run("steam-still", { "an": an }, 8.0), "an" if an else "aus")
	var tree := Engine.get_main_loop() as SceneTree
	while an and tree != null and runde == _runde:
		await tree.create_timer(NACHSEHEN_S).timeout
		if runde != _runde or not Helper.available:
			return
		_melden(await Helper.run("steam-still", {}, 8.0), "")


static func _melden(r: Dictionary, anlass: String) -> void:
	var z := zeile(r)
	if anlass == "" and z == _zuletzt:
		return
	_zuletzt = z
	Helper.hlog("steam-still%s: %s" % [(" " + anlass) if anlass != "" else "", z])


## Was der Helfer meldet, als eine Zeile fürs Protokoll (fremde Daten: Typen geprüft, Texte gekürzt).
static func zeile(r: Dictionary) -> String:
	if not r.has("aktiv"):
		return "keine Antwort (%s)" % Fremd.text(r.get("error"), "?", 60)
	var teile := PackedStringArray(["aktiv" if Fremd.ja(r.get("aktiv")) else "aus", "Fenster %d" % Fremd.zahl(r.get("gesehen")),
			"gesetzt %d" % Fremd.zahl(r.get("gesetzt"))])
	var letzter := Fremd.text(r.get("zuletzt"), "", 48)
	if letzter != "":
		teile.append("zuletzt " + letzter)
	var zurueck := Fremd.zahl(r.get("zurueck"))
	if zurueck > 0:
		teile.append("zurückgegeben %d" % zurueck)
	var aehnlich := Fremd.text(r.get("aehnlich"), "", 200)
	if aehnlich != "":
		teile.append("ähnlich: " + aehnlich)
	return ", ".join(teile)

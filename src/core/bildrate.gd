extends RefCounted
## Kurz mehr Bilder für die kleinen Fenster über dem Spiel oder einer App (Mitteilung, Erfolg, Leitfaden,
## Tastenzeile): Uzai ruht dort mit wenigen Bildern je Sekunde, eine weiche Bewegung braucht WEICH.
## Die Fenster teilen sich die Anhebung. Vorher merkte sich jedes den Ruhewert selbst: Standen zwei
## zugleich, stellte das erste beim Gehen dem zweiten die Ruherate zurück (es ruckte), und wechselte
## main die Rate inzwischen auf genau 60 (leichter Modus an einem 120-Hz-Bildschirm), blieb Uzai danach
## auf der Ruherate stehen.

const WEICH := 60

static var _halter := {}         ## Instanz-ID jedes Fensters, das die Anhebung gerade braucht
static var _vorher := -1         ## Ruhewert, der danach zurückkommt; -1: nichts angehoben


## Ein Fenster erscheint (mehrfach für dasselbe Fenster zählt einmal).
static func heben(wer: Object) -> void:
	_halter[wer.get_instance_id()] = true
	_anheben()


## Ein Fenster ist gegangen; beim letzten kommt der Ruhewert zurück.
static func senken(wer: Object) -> void:
	if not _halter.erase(wer.get_instance_id()):
		return
	if not haelt():
		if _vorher > 0 and Engine.max_fps == WEICH:
			Engine.max_fps = _vorher
		_vorher = -1


## main hat die Bildrate selbst gesetzt (Spiel beginnt oder endet, Guide, Ruhe): Der gemerkte Wert gilt
## nicht mehr. Steht noch ein Fenster, gilt die Anhebung für den neuen Wert weiter.
static func gesetzt() -> void:
	_vorher = -1
	if haelt():
		_anheben()


## Braucht noch ein Fenster die Anhebung? Ein Fenster, das ohne senken() freigegeben wurde, zählt nicht mehr.
static func haelt() -> bool:
	for id: int in _halter.keys():
		if not is_instance_id_valid(id):
			_halter.erase(id)
	return not _halter.is_empty()


static func _anheben() -> void:
	if Engine.max_fps > 0 and Engine.max_fps < WEICH:
		_vorher = Engine.max_fps
		Engine.max_fps = WEICH

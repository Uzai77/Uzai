extends RefCounted
## Freundschaftsanfragen beantworten (Punkt 11) – für den Freunde-Bereich und die Profile: A auf
## einer Anfrage an dich fragt, was passieren soll (Annehmen, Ablehnen, Profil, Später); Ablehnen
## erst nach einer kurzen Rückfrage. Nichts geschieht von selbst, gesendete Anfragen stehen nur da.
## Die Arbeit macht Social.answer_request.

const FR := preload("res://src/core/friend_requests.gd")
const FriendProfile := preload("res://src/ui/layers/friend_profile.gd")
const Main := preload("res://src/main.gd")


## „Annehmen“ heißt bei Anrufen „Answer“ – hier ist es eine Freundschaftsanfrage (Kontext „anfrage“).
static func accept_text() -> String:
	return TranslationServer.translate("Annehmen", "anfrage")


static func service(r: Dictionary) -> String:
	return "Steam" if str(r.get("source", "")) == "steam" else "Discord"


## A auf einer Anfrage. Gesendete: gleich das Profil.
static func ask(main: Main, r: Dictionary, done := Callable()) -> void:
	if str(r.get("dir", "")) != FR.IN:
		open_profile(main, r, done)
		return
	var name_ := str(r.get("name", ""))
	main.open_dialog("Anfrage von %s" % name_,
		"%s möchte auf %s mit dir befreundet sein. Wer das ist, zeigt „Profil“." % [name_, service(r)], [
		[accept_text(), func() -> void: accept(r, done)],
		["Ablehnen", func() -> void: decline(main, r, done)],
		["Profil", func() -> void: open_profile(main, r, done)],
		["Später", func() -> void: pass],
	], "friends")


static func accept(r: Dictionary, done := Callable()) -> void:
	var why: String = await Social.answer_request(r, true)
	if why != "":
		Toasts.show_toast("Annehmen ging nicht", why, "warning", { "ms": 6000 })
		return
	Toasts.show_toast("Ihr seid jetzt befreundet", "%s  ·  %s" % [str(r.get("name", "")), service(r)], "friends",
		{ "image": str(r.get("avatar", "")), "sound": "select", "ms": 4000 })
	if done.is_valid():
		done.call()


## Ablehnen erst nach Rückfrage; die Auswahl liegt dabei auf „Abbrechen“.
static func decline(main: Main, r: Dictionary, done := Callable()) -> void:
	main.open_dialog("Anfrage von %s ablehnen?" % str(r.get("name", "")),
		"Die Anfrage verschwindet aus deiner Liste. Befreunden geht später trotzdem noch – über eine neue Anfrage.", [
		["Ablehnen", func() -> void: _decline(r, done), "danger"],
		["Abbrechen", func() -> void: pass],
	], "friends", "warn")


static func _decline(r: Dictionary, done: Callable) -> void:
	var why: String = await Social.answer_request(r, false)
	if why != "":
		Toasts.show_toast("Ablehnen ging nicht", why, "warning", { "ms": 6000 })
		return
	Toasts.show_toast("Anfrage abgelehnt", "%s  ·  %s" % [str(r.get("name", "")), service(r)], "friends", { "ms": 3000 })
	if done.is_valid():
		done.call()


## Profil vorher ansehen: bei Steam die Profilseite wie bei Freunden (ohne Chat und Vergleichen),
## bei Discord das kleine Profil. Annehmen und Ablehnen gehen dort auch.
static func open_profile(main: Main, r: Dictionary, done := Callable()) -> void:
	var f := { "id": str(r.get("id", "")), "name": str(r.get("name", "")), "avatar": str(r.get("avatar", "")),
		"username": str(r.get("username", "")), "state": "offline", "game": "", "request": r, "request_done": done }
	var l
	if str(r.get("source", "")) == "steam":
		l = FriendProfile.new()
	else:
		l = load("res://src/ui/layers/discord_profile.gd").new()
	l.friend = f
	l.main = main
	main.open_layer(l)

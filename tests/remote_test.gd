extends Node
## Prüft die Handy-Eingabe von außen: startet eine Eingabe auf 127.0.0.1 und wartet auf den Text.
## Aufruf: godot --path . res://tests/remote_test.tscn  (dann mit curl die Adresse aufrufen)

func _ready() -> void:
	var url := Remote.phone_begin("t1", "Testschlüssel", "Hinweis", true, "https://www.steamgriddb.com/profile/preferences/api", "127.0.0.1")
	print("URL ", url)
	var got := [""]
	Remote.phone_text.connect(func(id: String, v: String) -> void:
		got[0] = id + "=" + v
	)
	var t0 := Time.get_ticks_msec()
	while got[0] == "" and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().process_frame
	print("ERHALTEN ", got[0])
	get_tree().quit()

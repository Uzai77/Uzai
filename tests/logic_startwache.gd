extends Node
## Die Wache nach dem Start (src/core/startwache.gd): wann Uzai sich nach vorn holt, wann der Controller auch ohne
## Fokus-Meldung zählt, wann sie den Nutzer in Ruhe lässt. Dazu, dass Nav und main sie so benutzen.
## Aufruf: godot --headless --path . res://tests/logic_startwache.tscn

const W := preload("res://src/core/startwache.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _lage(alter_ms: int, hatte: bool, extra := {}) -> Dictionary:
	var l := { "alter_ms": alter_ms, "hatte": hatte, "geholt": 0, "helfer": true, "idle_ms": 60000, "fg_eigen": false, "taste": false }
	l.merge(extra, true)
	return l


func _ready() -> void:
	print("Wache nach dem Start")
	check(W.schritt(_lage(800, false)) == "holen", "nie vorn gewesen: holen")
	check(W.schritt(_lage(800, false, { "helfer": false, "idle_ms": -1 })) == "holen", "nie vorn gewesen, Helfer noch nicht da: trotzdem versuchen")
	check(W.schritt(_lage(20000, false, { "helfer": false, "idle_ms": -1 })) == "holen",
			"… auch nach 20 s noch (der Helfer braucht am PC länger als die alten 7 s)")
	check(W.schritt(_lage(9000, true)) == "holen", "war vorn, ein Programm hat sich davorgesetzt (niemand an Maus oder Tastatur): zurückholen")
	check(W.schritt(_lage(9000, true, { "idle_ms": 300 })) == "ende", "war vorn, eben Maus oder Tastatur benutzt: Der Nutzer hat gewechselt – Ende")
	check(W.schritt(_lage(9000, true, { "helfer": false, "idle_ms": -1 })) == "warten", "war vorn, Helfer nicht da: abwarten statt raten")
	check(W.schritt(_lage(9000, true, { "idle_ms": -1 })) == "warten", "gleich nach dem eigenen Holen (Zeit unbekannt): abwarten")
	check(W.schritt(_lage(2000, false, { "idle_ms": 300 })) == "holen", "in den ersten Sekunden zählt der Klick, der Uzai gestartet hat, nicht als Wechsel")
	check(W.schritt(_lage(W.SCHONFRIST_MS + 1, false, { "idle_ms": 300 })) == "ende", "danach schon: Wer tippt oder klickt, wird nicht gestört")
	check(W.schritt(_lage(30000, true, { "idle_ms": 300, "taste": true })) == "holen", "am Controller gedrückt: holen, gleich was sonst war")
	check(W.schritt(_lage(5000, false, { "fg_eigen": true })) == "gilt" and W.schritt(_lage(5000, true, { "fg_eigen": true, "geholt": 99 })) == "gilt",
			"Windows führt Uzai als vorn: Der Controller zählt, nichts zu holen")
	check(W.schritt(_lage(5000, false, { "geholt": W.HOLEN_MAX })) == "ende" and W.schritt(_lage(5000, false, { "geholt": W.HOLEN_MAX - 1 })) == "holen",
			"höchstens %d Mal holen (kein Tauziehen)" % W.HOLEN_MAX)
	check(W.schritt({}) == "holen" and W.schritt({ "idle_ms": "kaputt", "geholt": null }) == "holen", "fehlende Angaben stören nicht")
	check(W.vorn_text({}, 1, 2).contains("Helfer noch nicht bereit")
			and W.vorn_text({ "fg_hwnd": 7, "fg_pid": 9, "fg_title": "Steam", "fg_class": "SDL_app", "idle_ms": 4200 }, 1, 2) == "„Steam“ (SDL_app)"
			and W.idle_text({ "idle_ms": 4200 }) == "4200 ms" and W.idle_text({}) == "?" and W.idle_text({ "idle_ms": "kaputt" }) == "?"
			and W.vorn_text({ "fg_hwnd": 1, "fg_pid": 2 }, 1, 2).contains("Uzais eigenes Fenster")
			and W.vorn_text({ "fg_hwnd": 5, "fg_pid": 2 }, 1, 2).contains("ein Fenster von Uzai"), "fürs Protokoll: wer vorn liegt")
	print("Einbau")
	var vor := Nav.vorn_gilt_bis
	Nav.vorn_gilt_bis = Time.get_ticks_msec() + 5000
	var gilt: bool = Nav._pad_allowed()
	Nav.vorn_gilt_bis = 0
	Nav.passthrough = true
	Nav.vorn_gilt_bis = Time.get_ticks_msec() + 5000
	var durchlass: bool = Nav._pad_allowed()
	Nav.passthrough = false
	Nav.vorn_gilt_bis = vor
	check(gilt and not durchlass, "Nav: Mit „gilt“ zählt der Controller ohne Fokus-Meldung – außer im Durchlass")
	var m := FileAccess.get_file_as_string("res://src/main.gd")
	var sv := m.substr(m.find("func _start_vorn("), 4200)
	check(sv.contains("Startwache.schritt(") and sv.contains("Nav.vorn_gilt_bis") and sv.contains("_start_bedient") and sv.contains("Startwache.DAUER_MS")
			and not m.contains("START_VORN_S"), "main: Die Wache läuft bis zum ersten Tastendruck, nicht nur vier Versuche lang")
	var oc := m.substr(m.find("func _on_command("), 400)
	check(oc.contains("_start_taste_holt()") and oc.find("_start_taste_holt()") < oc.find("_boot.taste()"),
			"main: Ein Druck am Controller ohne Fokus holt Uzai in der ersten Minute sofort nach vorn")
	var h := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	check(h.contains("idle_ms = [UzWin]::IdleMs()") and h.contains("GetLastInputInfo"), "Helfer: window-state nennt die Zeit seit der letzten Maus-/Tastatureingabe")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

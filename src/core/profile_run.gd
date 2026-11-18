extends Node
## Spiel-Profile anwenden (game_profile.gd); hängt am Launcher. Vor dem Start: Auflösung, HDR,
## Tonausgabe, Controller in Uzais Menü und die Aktionen; sobald das Spielfenster da ist: die
## Lautstärke des Spiels. Nach dem Spiel geht alles zurück – nur, was Uzai selbst umgestellt hat,
## und nur, wenn es noch so steht (wer währenddessen selbst umstellt, behält seine Wahl).
##
## Was Windows betrifft (Auflösung, HDR, Tonausgabe, Mikrofon, Discord-Status), steht vor dem
## Umstellen in profile/zurueck.json im Datenordner. Stürzt Uzai, das Spiel oder der PC ab – auch
## wenn der Wächter Uzai später neu startet –, stellt der nächste Start von Uzai es zurück. Die
## Datei liegt bewusst in einem Unterordner: Sicherungen nehmen sie nicht mit, ein Zurückspielen
## weckt also nie einen alten Stand. Controller und Pop-ups ändert Uzai nur im Speicher
## (Config.set_temp) – die vergisst ein Absturz von selbst.
##
## Die Auflösung setzt der Helfer nur vorübergehend (nichts in der Registrierung); zurück geht es
## mit dem dokumentierten Aufruf, der den gespeicherten Modus von Windows wieder setzt.
## Die Lautstärke eines Programms merkt sich Windows selbst. Uzai setzt sie bei jedem Start und
## stellt sie zurück, wenn das Spiel über Uzai beendet wird (before_quit); endet es von selbst,
## ist sein Ton schon weg, und Windows behält den Pegel des Profils.

const GameProfile := preload("res://src/core/game_profile.gd")
const MyStatus := preload("res://src/core/my_status.gd")
const Fremd := preload("res://src/core/fremd.gd")
const RESTORE_FILE := "profile/zurueck.json"
## Diese Teile betreffen Windows (oder Discord) und überstehen darum einen Absturz.
const LASTING := ["display", "hdr", "audio", "mic", "discord"]
const VOLUME_TRIES := 12          ## so oft (alle VOLUME_GAP_S) nach dem Ton des Spiels sehen
const VOLUME_GAP_S := 5.0
const DISCORD_WAIT_S := 120.0     ## nach einem Absturz so lange auf Discord warten

var active: Dictionary = {}       ## wirksames Profil des laufenden Spiels
var _undo: Dictionary = {}        ## was nach dem Spiel zurückgeht
var _gen := 0
var _volume: Dictionary = {}      ## { pids, was } – Pegel des Spiels vor dem Profil
## Was sich nach dem letzten Spiel nicht zurückstellen ließ, weil der Helfer nicht antwortete. Bleibt in der Datei
## und wird nachgeholt: sobald der Helfer wieder da ist, vor dem nächsten Spiel, spätestens beim nächsten Start.
var _offen: Dictionary = {}
const NACHHOLEN_S := 8.0


static func pending_path() -> String:
	return Config.path(RESTORE_FILE)


# --- Beim Start ------------------------------------------------------------------------------

## Vor dem Start des Spiels (Launcher.launch wartet darauf).
func apply(g: Dictionary) -> void:
	_gen += 1
	_undo = {}
	_volume = {}
	if not _offen.is_empty():
		# Erst das Ausstehende vom letzten Spiel: Sonst merkte sich dieses Profil den verstellten Stand als „vorher“.
		_offen = await _restore_windows(_offen)
		_write_pending()
	active = GameProfile.effective(GameProfile.own_of(g), GameProfile.template_for(g))
	if active.is_empty():
		return
	for k in GameProfile.PAD:
		if active.has(k):
			Config.set_temp(str(GameProfile.PAD[k][0]), float(active[k]))
	var acts: Array = active.get("actions", [])
	if acts.has("quiet"):
		Config.set_temp("notify.in_game", false)
	var problems := PackedStringArray()
	if Config.is_windows() and Helper.available:
		if active.has("display") or active.has("hdr"):
			Launcher.state.emit("Bildschirm wird für %s eingestellt …" % Library.display_title(g))
			problems.append_array(await _apply_display())
		if active.has("audio"):
			problems.append_array(await _apply_audio())
	if acts.has("mic_mute") and not Mixer.mic_muted:
		_remember("mic", true)
		await Mixer.set_mic(true)
		if not Mixer.mic_muted:
			_forget("mic")
	if acts.has("music_pause") and bool(Music.now.get("playing", false)):
		_undo["music"] = true
		Music.play_pause(false)
	if acts.has("discord_dnd"):
		_discord_dnd(_gen)          # Discord antwortet manchmal langsam: der Start wartet nicht darauf
	if not problems.is_empty():
		Toasts.show_toast("Profil nicht ganz angewendet", "\n".join(problems), "warning", { "ms": 8000, "overlay": true })


func _apply_display() -> PackedStringArray:
	var out := PackedStringArray()
	var info := GameProfile.parse_modes(await Helper.run("display-modes", { "hwnd": _hwnd() }, 10.0))
	if info.is_empty():
		out.append(tr("Uzai konnte den Bildschirm nicht abfragen."))
		return out
	var dev := str(info.device)
	if active.has("display"):
		var m: Dictionary = active.display
		if int(m.w) != int(info.w) or int(m.h) != int(info.h) or int(m.hz) != int(info.hz):
			_remember("display", dev)
			var r := GameProfile.reply(await Helper.run("display-set", { "device": dev, "w": int(m.w), "h": int(m.h), "hz": int(m.hz) }, 12.0))
			if not bool(r.get("ok", false)):
				_forget("display")
				if str(r.get("error", "")) == "mode":
					out.append(tr("%s bietet dieser Bildschirm nicht an.") % GameProfile.mode_text(m))
				else:
					out.append(tr("Windows hat %s abgelehnt.") % GameProfile.mode_text(m))
	if active.has("hdr"):
		var want := str(active.hdr)
		var now := str(info.hdr)
		if now in ["", "nein"]:
			if want == "an":
				out.append(tr("Dieser Bildschirm meldet kein HDR."))
		elif (now == "an") != (want == "an"):
			_remember("hdr", { "device": dev, "before": now, "set": want })
			var r := GameProfile.reply(await Helper.run("display-hdr", { "device": dev, "on": 1 if want == "an" else 0 }, 12.0))
			if not bool(r.get("ok", false)):
				_forget("hdr")
				out.append(tr("Windows hat HDR nicht umgestellt."))
	return out


func _apply_audio() -> PackedStringArray:
	var out := PackedStringArray()
	var want: Dictionary = active.audio
	var list := await _audio_list()
	if list.is_empty():
		out.append(tr("Uzai konnte die Audiogeräte nicht lesen."))
		return out
	var ids: Array = list.devices.map(func(d: Dictionary) -> String: return str(d.id))
	if not ids.has(str(want.id)):
		out.append(tr("%s ist gerade nicht angeschlossen.") % str(want.name))
		return out
	if str(list.current) == str(want.id):
		return out
	_remember("audio", { "before": str(list.current), "set": str(want.id) })
	var r := await Helper.run("audio-set", { "id": str(want.id) }, 8.0)
	if not r.ok:
		_forget("audio")
		out.append(tr("Windows hat die Tonausgabe nicht umgestellt."))
	return out


## { devices: [{ id, name }], current } oder {} (Helfer: audio-list).
func _audio_list() -> Dictionary:
	return _audio_aus(await Helper.run("audio-list", {}, 8.0))


static func _audio_aus(r: Dictionary) -> Dictionary:
	if not r.ok or not (r.result is Dictionary):
		return {}
	var devs: Array = []
	var cur := ""
	for d in (r.result as Dictionary).get("devices", []):
		if d is Dictionary:
			devs.append({ "id": str(d.get("id", "")), "name": str(d.get("name", "")) })
			if bool(d.get("default", false)):
				cur = str(d.get("id", ""))
	return { "devices": devs, "current": cur }


func _discord_dnd(gen: int) -> void:
	if not MyStatus.has_discord():
		return
	var before := MyStatus.discord_now()
	if not (before in ["online", "idle"]):
		return
	_remember("discord", before)
	var err := await MyStatus.set_discord("dnd")
	if gen != _gen:
		# Das Spiel war schneller zu Ende als Discord: gleich wieder zurück.
		if err == "":
			_discord_back(before)
		return
	if err != "":
		_forget("discord")
		Toasts.show_toast("Discord-Status nicht geändert", err, "discord", { "ms": 5000, "quiet": true, "overlay": true })


## Das Spielfenster ist da: Lautstärke des Spiels. Sein Ton erscheint oft erst nach dem Laden –
## darum eine Weile immer wieder nachsehen.
func on_window(_g: Dictionary) -> void:
	if not active.has("volume"):
		return
	var gen := _gen
	var level := int(active.volume)
	for i in VOLUME_TRIES:
		if gen != _gen or not Launcher.in_game:
			return
		var snap: Dictionary = await Mixer.snapshot()
		if gen != _gen:
			return
		for row in snap.get("rows", []):
			if str(row.get("id", "")) == "spiel":
				_volume = { "row": row, "was": int(row.get("level", 100)) }
				if int(row.get("level", 100)) != level:
					Mixer.set_level(row, level)
				return
		await get_tree().create_timer(VOLUME_GAP_S).timeout


## Gleich wird das Spiel über Uzai beendet: Pegel des Programms zurück, solange es noch Ton hat.
func before_quit() -> void:
	if _volume.is_empty():
		return
	var row: Dictionary = _volume.row
	var was := int(_volume.was)
	_volume = {}
	if was == int(active.get("volume", was)):
		return
	if Config.is_windows() and Helper.available:
		var pids: Array = (row.get("pids", []) as Array).map(func(x: Variant) -> int: return int(x)).filter(func(x: int) -> bool: return x > 4)
		if not pids.is_empty():
			await Helper.run("mixer-set", { "pids": pids.slice(0, 64), "level": was, "mute": -1 }, 3.0)
	else:
		Mixer.set_level(row, was)


# --- Nach dem Spiel --------------------------------------------------------------------------

## Spielende (Launcher._finish) oder Fehlstart: alles zurück.
func restore() -> void:
	_gen += 1
	var u := _undo
	_undo = {}
	active = {}
	_volume = {}
	Config.clear_temp()
	if u.is_empty():
		return
	if bool(u.get("music", false)) and not bool(Music.now.get("playing", false)):
		Music.play_pause(false)
	if u.has("mic") and Mixer.mic_muted:
		Mixer.set_mic(false)
	u.erase("mic")
	if u.has("discord"):
		_discord_back(str(u.discord))
		u.erase("discord")
	var gen := _gen
	var rest := await _restore_windows(u)
	if gen != _gen:
		return          # inzwischen läuft schon das nächste Spiel
	_offen = rest
	_write_pending()
	if not _offen.is_empty():
		_nachholen(gen)


## Der Helfer antwortete beim Zurückstellen nicht (er startete gerade neu): warten, bis er wieder da ist, und es
## einmal nachholen. Früher blieben Auflösung, HDR oder Tonausgabe dann verstellt, und der Merkzettel war gelöscht.
func _nachholen(gen: int) -> void:
	await get_tree().create_timer(NACHHOLEN_S).timeout
	if not Helper.available:
		await Helper.helper_ready
	if gen != _gen or _offen.is_empty():
		return
	Helper.hlog("Profil: Zurückstellen wird nachgeholt (%s)" % ", ".join(PackedStringArray(_offen.keys())))
	var rest := await _restore_windows(_offen)
	if gen != _gen:
		return
	_offen = rest
	_write_pending()


func _discord_back(before: String) -> void:
	if MyStatus.has_discord() and MyStatus.discord_now() == "dnd" and before in ["online", "idle"]:
		await MyStatus.set_discord(before)


## Bildschirm, HDR, Tonausgabe (und nach einem Absturz das Mikrofon) zurück. Gibt zurück, was offen bleibt, weil der
## Helfer nicht antwortete ({} = alles erledigt). Eine Absage von Windows bleibt nicht offen: Die wiederholte sich nur.
func _restore_windows(u: Dictionary) -> Dictionary:
	var offen := {}
	if not Config.is_windows():
		return offen
	if not Helper.available:
		return offen_ohne_helfer(u)
	if u.has("display") and Helper.ohne_antwort(await Helper.run("display-reset", { "device": str(u.display) }, 12.0)):
		offen["display"] = u.display
	if u.get("hdr") is Dictionary:
		var h: Dictionary = u.hdr
		# Der Helfer stellt nur um, was nicht schon so steht.
		if Helper.ohne_antwort(await Helper.run("display-hdr", { "device": str(h.get("device", "")), "on": 1 if str(h.get("before", "")) == "an" else 0 }, 12.0)):
			offen["hdr"] = h
	if u.get("audio") is Dictionary:
		var a: Dictionary = u.audio
		var gefragt := await Helper.run("audio-list", {}, 8.0)
		var list := _audio_aus(gefragt)
		if Helper.ohne_antwort(gefragt):
			offen["audio"] = a
		elif not list.is_empty():
			var ids: Array = list.devices.map(func(d: Dictionary) -> String: return str(d.id))
			var back := GameProfile.audio_back(str(list.current), str(a.get("set", "")), str(a.get("before", "")), ids)
			if back != "" and Helper.ohne_antwort(await Helper.run("audio-set", { "id": back }, 8.0)):
				offen["audio"] = a
	if bool(u.get("mic", false)):
		if Helper.ohne_antwort(await Helper.run("mic", { "mute": 0 }, 4.0)):
			offen["mic"] = true
		Mixer.refresh_mic()
	return offen


## Ohne Helfer bleibt alles offen, was Windows betrifft.
static func offen_ohne_helfer(u: Dictionary) -> Dictionary:
	var offen := {}
	for k in ["display", "hdr", "audio", "mic"]:
		if u.has(k):
			offen[k] = u[k]
	return offen


## Beim Start von Uzai: ging das letzte Spiel nicht sauber zu Ende (Absturz von Uzai, des Spiels
## oder des PCs), jetzt zurückstellen, was Uzai damals umgestellt hat.
func restore_pending() -> void:
	var p := read_pending(pending_path())
	if p.is_empty():
		return
	if not Config.is_windows():
		_remove_pending()
		return
	if not Helper.available:
		await Helper.helper_ready
	var gen := _gen
	var rest := await _restore_windows(p)
	if p.has("discord"):
		var t0 := Time.get_ticks_msec()
		while not MyStatus.has_discord() and Time.get_ticks_msec() - t0 < DISCORD_WAIT_S * 1000.0:
			await get_tree().create_timer(2.0).timeout
		await _discord_back(str(p.discord))
	# Was auch jetzt ohne Antwort blieb, steht weiter in der Datei (nächster Start). Läuft schon ein Spiel, gehört der
	# gemerkte Stand ihm.
	if gen == _gen:
		_offen = rest
		_write_pending()
	var getan := p.duplicate()
	for k in rest:
		getan.erase(k)
	if not getan.is_empty():
		Toasts.show_toast("Nach dem letzten Spiel zurückgestellt", GameProfile.restored_text(getan), "check", { "ms": 5000, "quiet": true })


# --- Gemerkter Stand -------------------------------------------------------------------------

func _remember(k: String, v: Variant) -> void:
	_undo[k] = v
	_write_pending()


func _forget(k: String) -> void:
	_undo.erase(k)
	_write_pending()


## Hat ein Spiel-Profil die Tonausgabe umgestellt (und noch nicht zurück)? Dann hält das feste Gerät still
## (src/core/tonwahl.gd).
func ton_umgestellt() -> bool:
	return _undo.has("audio") or _offen.has("audio")


## Ohne .bak/.tmp (wie die Absturz-Markierung): eine liegengebliebene Vorfassung würde sonst
## später einen alten Stand zurückholen.
func _write_pending() -> void:
	var keep := gemerkt(_undo, _offen)
	if keep.is_empty():
		_remove_pending()
		return
	var p := pending_path()
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(keep))
		f.close()


## Was in die Datei gehört: das Umgestellte des laufenden Spiels, sonst das noch Ausstehende vom letzten.
static func gemerkt(undo: Dictionary, offen: Dictionary) -> Dictionary:
	var keep := {}
	for k in LASTING:
		if undo.has(k):
			keep[k] = undo[k]
		elif offen.has(k):
			keep[k] = offen[k]
	return keep


func _remove_pending() -> void:
	if FileAccess.file_exists(pending_path()):
		DirAccess.remove_absolute(pending_path())


## Gemerkter Stand, geprüft (nur bekannte Teile, Gerät und Kennungen wie beim Setzen).
static func read_pending(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > 8192:
		return {}
	var v: Variant = Fremd.json_roh(f.get_as_text())
	return GameProfile.clean_pending(v)


func _hwnd() -> int:
	return DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window().get_window_id())

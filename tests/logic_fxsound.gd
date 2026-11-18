extends Node
## FxSound aus Uzai (src/core/fxsound.gd) und das feste Ausgabegerät (src/core/tonwahl.gd): Statusdatei lesen,
## Werte prüfen, Entscheidung des Wächters. Die Befehlszeile selbst prüft tests/helfer_cs.ps1.
## Aufruf: godot --headless --path . res://tests/logic_fxsound.tscn

const Fx := preload("res://src/core/fxsound.gd")
const Tw := preload("res://src/core/tonwahl.gd")

const TV := "{0.0.0.00000000}.{6f1c2a10-0000-4000-8000-00000000a001}"
const KH := "{0.0.0.00000000}.{6f1c2a10-0000-4000-8000-00000000a002}"
const FX := "{0.0.0.00000000}.{6f1c2a10-0000-4000-8000-00000000a0ff}"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _geraete(std: String, mit_tv := true, mit_fx := false) -> Array:
	var out: Array = [{ "id": KH, "name": "Kopfhörer (Xbox Wireless Headset)", "ff": 3, "default": std == KH }]
	if mit_tv:
		out.append({ "id": TV, "name": "LG TV (NVIDIA High Definition Audio)", "ff": 9, "default": std == TV })
	if mit_fx:
		out.append({ "id": FX, "name": "FxSound Speakers (FxSound Audio Enhancer)", "ff": 1, "default": std == FX })
	return out


func _ready() -> void:
	print("FxSound: Fassung und Werte")
	check(Fx.version_reicht("1.2.11.0") and Fx.version_reicht("1.2.15.0") and Fx.version_reicht("1.3.0") and Fx.version_reicht("2.0.0.0"),
			"ab 1.2.11 nimmt FxSound Befehle und meldet seinen Stand")
	check(not Fx.version_reicht("1.2.10.0") and not Fx.version_reicht("1.1.22.0") and not Fx.version_reicht("") and not Fx.version_reicht("x.y.z")
			and not Fx.version_reicht("1.2") and not Fx.version_reicht("1.2.999999"), "ältere und unlesbare Fassungen: nein")
	check(Fx.wert_ok("LG TV (NVIDIA High Definition Audio)") and Fx.wert_ok("Kopfhörer (2- Realtek(R) Audio)") and Fx.wert_ok("Bass Boost", Fx.NAME_MAX),
			"Namen mit Leerzeichen, Klammern und Umlauten gehen")
	check(not Fx.wert_ok("TV\" --power=0 --preset=\"x") and not Fx.wert_ok("a\nb") and not Fx.wert_ok("a\tb") and not Fx.wert_ok("") and not Fx.wert_ok("x".repeat(201))
			and not Fx.wert_ok("p".repeat(65), Fx.NAME_MAX), "Anführungszeichen, Steuerzeichen, leer, zu lang: nie in einen Befehl")
	check(Fx.ist_eigenes("FxSound Speakers (FxSound Audio Enhancer)") and not Fx.ist_eigenes("Lautsprecher (Realtek(R) Audio)"), "FxSounds eigenes Gerät am Namen erkannt")

	print("FxSound: Statusdatei")
	var text := JSON.stringify({ "version": "1.2.15.0", "power": true,
		"presets": { "built_in": [{ "name": "General", "modified": false }, { "name": "Gaming", "modified": true }, "kaputt", { "name": "Bö\"se" }],
			"user_defined": [{ "name": "Mein Profil" }, { "name": "Gaming" }, { "name": 7 }] },
		"selected_preset": "Gaming", "output_devices": ["LG TV (NVIDIA High Definition Audio)", "Kopfhörer (Xbox Wireless Headset)", 5, "x\ny"],
		"selected_output": "LG TV (NVIDIA High Definition Audio)", "equalizer": { "num_bands": 10 }, "effects": { "bass": 3.0 } })
	var st := Fx.status(text)
	check(bool(st.ok) and bool(st.an) and str(st.version) == "1.2.15.0" and str(st.profil) == "Gaming", "an, Fassung und gewähltes Profil gelesen")
	check(st.profile == ["General", "Gaming", "Mein Profil", "7"], "Profile: eingebaute zuerst, ohne doppelte und ohne unsendbare (%s)" % str(st.profile))
	check(st.geraete == ["LG TV (NVIDIA High Definition Audio)", "Kopfhörer (Xbox Wireless Headset)"] and str(st.geraet) == "LG TV (NVIDIA High Definition Audio)",
			"Ausgabegeräte ohne Fremdes, gewähltes Gerät gelesen")
	check(not bool(Fx.status("").ok) and not bool(Fx.status("kein json").ok) and not bool(Fx.status("[1,2]").ok) and not bool(Fx.status("x".repeat(Fx.STATUS_MAX + 1)).ok),
			"leer, kaputt, Liste statt Verzeichnis, zu groß: kein Stand")
	var falsch := Fx.status(JSON.stringify({ "power": "ja", "presets": [], "selected_preset": ["x"], "output_devices": "TV", "selected_output": 5 }))
	check(bool(falsch.ok) and not bool(falsch.an) and (falsch.profile as Array).is_empty() and str(falsch.profil) == "" and (falsch.geraete as Array).is_empty(),
			"falsche Arten in der Datei: kein Fehler, nichts übernommen")

	print("FxSound: Antwort des Helfers")
	var gut := Fx.stand({ "ok": true, "result": { "da": true, "laeuft": true, "version": "1.2.15.0", "json": text } })
	check(bool(gut.da) and bool(gut.laeuft) and bool(gut.bedienbar) and not bool(gut.alt) and bool(gut.an) and str(gut.profil) == "Gaming" and Fx.kurz(gut) == "Gaming",
			"läuft und meldet seinen Stand: bedienbar")
	var alt := Fx.stand({ "ok": true, "result": { "da": true, "laeuft": true, "version": "1.2.9.0", "alt": true } })
	check(bool(alt.alt) and not bool(alt.bedienbar) and Fx.kurz(alt) == "Zu alt", "läuft, aber zu alt: nicht bedienbar")
	var zu := Fx.stand({ "ok": true, "result": { "da": true, "laeuft": false, "version": "1.2.15.0" } })
	check(bool(zu.da) and not bool(zu.laeuft) and not bool(zu.bedienbar) and Fx.kurz(zu) == "Läuft nicht", "installiert, läuft nicht")
	check(not bool(Fx.stand({}).da) and not bool(Fx.stand({ "ok": false, "error": "nur unter Windows" }).da) and not bool(Fx.stand({ "ok": true, "result": "x" }).da)
			and Fx.kurz(Fx.stand({})) == "Nicht installiert", "keine oder kaputte Antwort: nichts da")
	var stumm := Fx.stand({ "ok": true, "result": { "da": true, "laeuft": true, "version": "1.2.15.0" } })
	check(not bool(stumm.bedienbar) and Fx.kurz(stumm) == "Antwortet nicht", "läuft, aber ohne Stand: nicht bedienbar")
	var aus := Fx.stand({ "ok": true, "result": { "da": true, "laeuft": true, "version": "1.2.15.0", "json": text.replace("\"power\":true", "\"power\":false") } })
	check(bool(aus.bedienbar) and not bool(aus.an) and Fx.kurz(aus) == "Aus", "Klangverbesserung aus")

	print("Geräte lesen")
	var roh := Tw.geraete_aus({ "ok": true, "result": { "devices": [
		{ "id": TV, "name": "LG TV (NVIDIA High Definition Audio)", "default": true, "ff": 9 }, { "id": KH, "name": "Kopf\"hörer", "default": false, "ff": 3 },
		{ "id": "kaputt", "name": "x" }, "kaputt", { "id": TV, "name": "doppelt" }] } })
	check(roh.size() == 2 and str(roh[0].id) == TV and bool(roh[0].default) and int(roh[0].ff) == 9, "Kennungen geprüft, ohne doppelte")
	check(str(roh[1].name) == "", "ein Name mit Anführungszeichen bleibt leer (nur über Windows wählbar)")
	check(Tw.geraete_aus({}).is_empty() and Tw.geraete_aus({ "ok": false }).is_empty() and Tw.geraete_aus({ "ok": true, "result": [] }).is_empty(),
			"keine Antwort: keine Geräte")
	check(Tw.signatur(_geraete(TV)) != Tw.signatur(_geraete(KH, false)) and Tw.signatur(_geraete(TV)) != Tw.signatur(_geraete(KH))
			and Tw.signatur(_geraete(TV)) == Tw.signatur(_geraete(TV)), "Signatur ändert sich, wenn ein Gerät kommt, geht oder der Standard wechselt")

	print("Festes Gerät: Windows führt")
	var da := Tw.finde(_geraete(KH), TV, "")
	check(str(da.get("id", "")) == TV and Tw.schritt(_geraete(KH), da, false, false, false) == "windows", "ein anderes Gerät ist Standard: zurück auf das feste")
	check(Tw.schritt(_geraete(TV), Tw.finde(_geraete(TV), TV, ""), true, false, false) == "", "das feste ist schon Standard: nichts")
	check(Tw.finde(_geraete(KH, false), TV, "LG TV (NVIDIA High Definition Audio)").is_empty() and Tw.schritt(_geraete(KH, false), {}, true, false, true) == "",
			"das feste ist weg (Fernseher aus): nichts – kein Ausweichen, kein Fehler")
	var neu_id := "{0.0.0.00000000}.{6f1c2a10-0000-4000-8000-00000000b777}"
	var umbenannt: Array = [{ "id": neu_id, "name": "LG TV (NVIDIA High Definition Audio)", "ff": 9, "default": false }]
	check(str(Tw.finde(umbenannt, TV, "LG TV (NVIDIA High Definition Audio)").get("id", "")) == neu_id, "neue Kennung, gleicher Name: wiedererkannt")

	print("Festes Gerät: FxSound führt")
	var mit_fx := _geraete(FX, true, true)
	var tv := Tw.finde(mit_fx, TV, "")
	check(Tw.fx_fuehrt(mit_fx) and not Tw.fx_fuehrt(_geraete(TV, true, true)), "FxSound führt, wenn sein Gerät der Standard von Windows ist")
	check(Tw.schritt(mit_fx, tv, true, false, true) == "fxsound", "Geräte haben sich geändert (Fernseher wieder da): FxSound auf das feste Gerät")
	check(Tw.schritt(mit_fx, tv, false, false, true) == "", "nichts geändert: FxSound in Ruhe lassen (was man dort von Hand wählt, bleibt)")
	check(Tw.schritt(mit_fx, tv, false, true, true) == "fxsound", "ein Versuch steht noch aus: noch einmal")
	check(Tw.schritt(mit_fx, tv, true, false, false) == "", "FxSound nicht bedienbar (zu alt, antwortet nicht): nichts – nie an FxSound vorbei umstellen")
	check(Tw.schritt(mit_fx, { "id": TV, "name": "", "default": false }, true, false, true) == "", "ohne sendbaren Namen: nichts")
	check(Tw.schritt(mit_fx, {}, true, true, true) == "", "das feste Gerät fehlt: nichts")

	print("Auswahl in Uzai")
	var a := Tw.auswahl(mit_fx, "LG TV (NVIDIA High Definition Audio)")
	var eigenes := func(d: Dictionary) -> bool: return Fx.ist_eigenes(str(d.name))
	check((a.devices as Array).size() == 2 and str(a.current) == TV and not (a.devices as Array).any(eigenes),
			"FxSound führt: sein eigenes Gerät steht nicht zur Wahl, aktiv ist, worauf FxSound ausgibt")
	var b := Tw.auswahl(_geraete(KH), "LG TV (NVIDIA High Definition Audio)")
	check(str(b.current) == KH and (b.devices as Array).size() == 2 and str(b.devices[0].kind) == "kopfhoerer", "Windows führt: aktiv ist das Standardgerät")
	check(str(Tw.auswahl(mit_fx, "").current) == "", "FxSound führt, Stand unbekannt: nichts als aktiv markiert")

	print("Nicht gegeneinander arbeiten")
	check(Tw.darf_zurueck([], 100000) and Tw.darf_zurueck([90000, 95000, 99000], 100000) and not Tw.darf_zurueck([50000, 90000, 95000, 99000], 100000)
			and Tw.darf_zurueck([1000, 2000, 3000, 4000], 100000), "höchstens viermal in einer Minute zurückstellen")
	var tw_src := FileAccess.get_file_as_string("res://src/core/tonwahl.gd")
	check(tw_src.contains("p.ton_umgestellt()") and FileAccess.get_file_as_string("res://src/core/profile_run.gd").contains("func ton_umgestellt()"),
			"ruht, solange ein Spiel-Profil die Tonausgabe umgestellt hat")
	check(str(Config.DEFAULTS.ton.fest_id) == "" and not bool(Config.DEFAULTS.ton.fxsound_start) and "ton" in load("res://src/core/profiles.gd").SHARED,
			"voreingestellt: kein festes Gerät, FxSound startet nicht von selbst; gilt für den ganzen PC")
	var helfer := FileAccess.get_file_as_string("res://helper/uzai-helper.ps1")
	var call := helfer.substr(helfer.find("function Fx-Call("), 2600)
	check(call.contains("if (-not $laeuft) { return $out }") and call.find("if (-not $laeuft) { return $out }") < call.find("Fx-Zeile $exe $a"),
			"Helfer: kein Befehl an ein FxSound, das nicht läuft (der Aufruf würde es starten)")
	check(call.contains("--status") and not helfer.substr(helfer.find("function Fx-Zeile("), 900).contains("Start-Process"), "Helfer: Stand über --status, Start ohne Shell")

	print("")
	print("Ergebnis: %s" % ("alles ok" if fails == 0 else "%d Fehler" % fails))
	get_tree().quit(1 if fails > 0 else 0)

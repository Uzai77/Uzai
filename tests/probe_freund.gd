extends "res://tests/probe_base.gd"
## Probe Freundestest (ohne Netz, nachgebaute Sandbox): Einladung mit Code und QR-Code, „Mila möchte rein“,
## zwei Figuren im Zimmer (Mila winkt, mit Namen und Schnellsatz).
## Aufruf: siehe docs/AGENTEN.md (xvfb-run … --uzai-script=res://tests/probe_freund.gd --uzai-out=<ordner>)

const ZN := preload("res://src/room/zimmer_netz.gd")
const P := preload("res://src/room/netz_protokoll.gd")
const FT := preload("res://src/room/freundestest.gd")
const EinladungUi := preload("res://src/room/einladung_ui.gd")


class Nachbau extends ZN.Sitzung:
	var rein := PackedByteArray()

	func _init() -> void:
		leitung = ZN.Leitung.new("gastgeber", true)

	func schicken(_b: PackedByteArray) -> void:
		pass

	func beenden() -> void:
		pass

	func pumpen(jetzt: float) -> Array:
		var b := rein
		rein = PackedByteArray()
		return leitung.eingang(b, jetzt)

	func laeuft() -> bool:
		return true


func run() -> void:
	Config.set_value("controller.glyphs", "xbox")
	Config.set_value("room.online_test", true)
	FT.abschottung_ok = true
	main.goto("games")
	await wait(1.2)
	main.open_room(true)
	await wait(2.5)
	var z: Control = Nav.top_layer()
	var sb := Nachbau.new()
	var ft: Node = FT.gastgeber_starten(get_tree(), func(_r: String) -> ZN.Sitzung: return sb, 4242, true)
	sb.rein.append_array(ZN.rahmen(ZN.STAND, PackedByteArray([1, 3, 4])))
	await wait(0.3)
	var e: Dictionary = ft.einladen("Mila", 60)
	var l = EinladungUi.new()
	l.ft = ft
	main.open_layer(l)
	await shot("freund_1_einladung", 1.6)
	await press("b", 1, 0.5)
	sb.rein.append_array(ZN.rahmen(ZN.KLOPFT, (e.kennung as PackedByteArray) + "a1b2c3d4e5f60718".hex_decode()))
	await shot("freund_2_anklopfen", 1.4)
	await press("a", 1, 0.6)
	var pk := func(art: String, d: Dictionary) -> void:
		sb.rein.append_array(ZN.rahmen(ZN.EMPFANGEN, PackedByteArray([0]) + P.schreiben(art, d)))
	sb.rein.append_array(ZN.rahmen(ZN.STAND, PackedByteArray([6, 0, 0])))
	pk.call("hallo", { "geraet": "uzai" })
	pk.call("figur", { "figur": { "person": "ben" }, "tier": {} })
	await wait(0.4)
	# Mila steht vor dir und schaut dich an, winkt und sagt „Hallo!“.
	z.set("blick", "schulter")
	var yaw := float(z.get("yaw"))
	var vorn := Vector3(-sin(yaw), 0, -cos(yaw))
	var p: Vector3 = (z.get("pos") as Vector3) + vorn * 2.4 + Vector3(-vorn.z, 0, vorn.x) * 0.4
	pk.call("pos", P.pos_aus(p, yaw + PI, 0.0))
	await wait(1.0)
	pk.call("emote", { "id": "winken" })
	pk.call("satz", { "id": "hallo" })
	await shot("freund_3_zwei_figuren", 1.3)
	print("Figuren: ", ft.figuren().keys(), " Besucher: ", z.get("_besucher").call("anzahl"))
	ft.beenden("offline")

extends RefCounted
## Die Menschen im Zimmer: Figuren aus „Characters PSX“ von Elbolilloduro (assets/figur/psx,
## Herkunft und Bedingungen in assets/figur/LIZENZ.txt) – je Figur ein Modell mit Mixamo-Skelett
## und einer eigenen Textur. Beim ersten Gebrauch einer Figur wird sie einmal aufbereitet:
##   – Ecken in die Ruhelage des Skeletts gerechnet (Meter, Füße auf dem Boden, Hüfte über dem
##     Ursprung, Blick nach +z), Frauen auf HOEHE.w, Männer auf HOEHE.m Scheitelhöhe gebracht.
##   – Ruhelage der Knochen ohne Drehung (nur Gelenkpunkte), Knochennamen ohne „mixamorig_“: die
##     Posen in avatar.gd rechnen im Körperrahmen, die Arme kommen aus der A-Haltung nach unten
##     (arm_ab).
##   – Das Netz in zwei Teile: oben (Brust, Arme, Kopf) und unten (Becken, Beine, Füße). Die
##     Ich-Ansicht blendet „oben“ aus, beim Blick nach unten sind Bauch, Beine und Füße da.
##   – Kopfmitte und -maße (Kamera der Ich-Ansicht, Editor).
##
## Uzai lädt nur die mitgelieferten, beim Bauen importierten Modelle – nie Dateien von außen.

const D := preload("res://src/room/figur/figur_daten.gd")
const ORDNER := "res://assets/figur/psx/"
## Scheitelhöhe je Art (Meter).
const HOEHE := { "w": 1.67, "m": 1.78 }
const UNTEN := ["Hips", "Spine", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "LeftToe_End", "RightUpLeg", "RightLeg", "RightFoot",
	"RightToeBase", "RightToe_End"]
const ARM_L := ["LeftArm", "LeftHand"]
const ARM_R := ["RightArm", "RightHand"]

static var _d := {}


## Alles Aufbereitete einer Figur (einmal je Sitzung): namen, eltern, reihe, rest (lokal), global
## (Ruhelage), haut (Skin), netze [oben, unten], textur, kopf_mitte, kopf_r (Halbachsen),
## huefte (Höhe), arm_ab {Knochen: Basis}. Unbekannte Figur: die erste.
static func daten(person: String) -> Dictionary:
	if not D.gueltig(D.PERSONEN, person):
		person = str(D.PERSONEN[0][0])
	if not ResourceLoader.exists(ORDNER + person + ".fbx"):
		return {}   # Ohne die Modelle (eigener Build aus dem öffentlichen Repository): keine Figur, siehe vorhanden().
	if not _d.has(person):
		_d[person] = _aufbereiten(person)
	return _d[person]


## Liegen die Modelle bei? Sie dürfen im gebauten Uzai mitkommen, aber nicht ins öffentliche Repository (Bedingung des
## Autors, assets/figur/LIZENZ.txt). Wer Uzai selbst aus dem Quelltext baut, hat sie nicht – dann bleibt das Zimmer ohne
## sichtbare Figur (avatar.gd bauen), alles andere geht.
static func vorhanden() -> bool:
	return ResourceLoader.exists(ORDNER + str(D.PERSONEN[0][0]) + ".fbx")


## Ein neues Skelett in Ruhelage (je Figur eines; Netze und Haut sind geteilt).
static func skelett(d: Dictionary) -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "skelett"
	for i in (d.namen as Array).size():
		sk.add_bone(str(d.namen[i]))
	for i in (d.namen as Array).size():
		sk.set_bone_parent(i, int(d.eltern[i]))
		sk.set_bone_rest(i, d.rest[i])
	sk.reset_bone_poses()
	return sk


static func _aufbereiten(person: String) -> Dictionary:
	var wurzel := (load(ORDNER + person + ".fbx") as PackedScene).instantiate()
	var sk: Skeleton3D = wurzel.find_children("*", "Skeleton3D", true, false)[0]
	var mi: MeshInstance3D = wurzel.find_children("*", "MeshInstance3D", true, false)[0]
	var n := sk.get_bone_count()
	var namen: Array = []
	var eltern: Array = []
	var g0: Array = []
	for i in n:
		namen.append(sk.get_bone_name(i).trim_prefix("mixamorig_").trim_prefix("mixamorig:"))
		eltern.append(sk.get_bone_parent(i))
		g0.append(sk.get_bone_global_rest(i))
	# Bindungen der Haut → Knochen und ihre Abbildung von Netz- in Skelettraum.
	var haut := mi.skin
	var bind_knochen := PackedInt32Array()
	var bind_trafo: Array = []
	for j in haut.get_bind_count():
		var b := haut.get_bind_bone(j)
		if b < 0:
			b = sk.find_bone(haut.get_bind_name(j))
		bind_knochen.append(maxi(b, 0))
		bind_trafo.append((g0[maxi(b, 0)] as Transform3D) * haut.get_bind_pose(j))
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nv: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var we: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var nb := bo.size() / maxi(v.size(), 1)
	# Ecken in der Ruhelage (gewichtet über ihre Knochen), Bindungen → Knochennummern.
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var dom := PackedInt32Array()
	pos.resize(v.size())
	nor.resize(v.size())
	dom.resize(v.size())
	for k in v.size():
		var p := Vector3.ZERO
		var q := Vector3.ZERO
		var summe := 0.0
		var best := -1.0
		for j in nb:
			var w := we[k * nb + j]
			var bi := bo[k * nb + j]
			if w <= 0.0 or bi >= bind_trafo.size():
				continue
			var t: Transform3D = bind_trafo[bi]
			p += t * v[k] * w
			q += (t.basis * nv[k]) * w
			summe += w
			if w > best:
				best = w
				dom[k] = bind_knochen[bi]
		pos[k] = p / maxf(summe, 1e-6)
		nor[k] = q.normalized() if q.length_squared() > 0.0 else Vector3.UP
		for j in nb:
			var bi2 := bo[k * nb + j]
			bo[k * nb + j] = bind_knochen[bi2] if bi2 < bind_knochen.size() else 0
	# Maßstab: Scheitel auf die Höhe der Art, Füße auf den Boden, die Hüfte über dem Ursprung.
	var unten_y := INF
	var oben_y := -INF
	for p in pos:
		unten_y = minf(unten_y, p.y)
		oben_y = maxf(oben_y, p.y)
	var art := str(D.feld_von(D.PERSONEN, person, 2, "w"))
	var s: float = float(HOEHE.get(art, 1.7)) / maxf(oben_y - unten_y, 0.5)
	var hp := (g0[maxi(namen.find("Hips"), 0)] as Transform3D).origin
	var versatz := Vector3(-hp.x, -unten_y, -hp.z)
	for k in pos.size():
		pos[k] = (pos[k] + versatz) * s
	var g1: Array = []
	for i in n:
		g1.append(Transform3D(Basis(), ((g0[i] as Transform3D).origin + versatz) * s))
	var rest: Array = []
	for i in n:
		var pi: int = eltern[i]
		rest.append((g1[i] as Transform3D) if pi < 0 else (g1[pi] as Transform3D).affine_inverse() * (g1[i] as Transform3D))
	var neue_haut := Skin.new()
	for i in n:
		neue_haut.add_named_bind(str(namen[i]), (g1[i] as Transform3D).affine_inverse())
	# Netz geteilt nach der Mehrheit der Ecken eines Dreiecks (oben/unten).
	var unten_set := {}
	for nm: String in UNTEN:
		unten_set[namen.find(nm)] = true
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var oben := PackedInt32Array()
	var unten := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var u := 0
		for e in 3:
			if unten_set.has(dom[idx[t + e]]):
				u += 1
		if u >= 2:
			unten.append_array([idx[t], idx[t + 1], idx[t + 2]])
		else:
			oben.append_array([idx[t], idx[t + 1], idx[t + 2]])
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var netze: Array = [_netz(oben, pos, nor, uv, bo, we, nb), _netz(unten, pos, nor, uv, bo, we, nb)]
	# Kopf: Mitte und Halbachsen (Kamera der Ich-Ansicht, Editor). Höhe vom Kopfgelenk bis
	# zum Scheitel, Breite und Tiefe aus den Ecken über dem Kinn (ohne herabhängende Haare), mittig
	# über dem Kopfgelenk; seitlich das 90. Perzentil, damit einzelne Strähnen nicht zählen.
	var kopf_i := namen.find("Head")
	var kg := (g1[kopf_i] as Transform3D).origin
	var scheitel := (g1[namen.find("HeadTop_End")] as Transform3D).origin.y if namen.has("HeadTop_End") else kg.y + 0.2
	var ab := kg.y + (scheitel - kg.y) * 0.3
	var seiten := PackedFloat32Array()
	var z_lo := INF
	var z_hi := -INF
	for k in pos.size():
		if dom[k] == kopf_i and pos[k].y > ab:
			seiten.append(absf(pos[k].x - kg.x))
			z_lo = minf(z_lo, pos[k].z)
			z_hi = maxf(z_hi, pos[k].z)
	seiten.sort()
	var breit := seiten[int(seiten.size() * 0.9)] if seiten.size() > 0 else 0.08
	var lo := Vector3(kg.x - breit, kg.y, z_lo if z_lo < INF else kg.z - 0.1)
	var hi := Vector3(kg.x + breit, scheitel, z_hi if z_hi > -INF else kg.z + 0.1)
	# Arme aus der A-Haltung nach unten: Drehung vom Oberarm zur Senkrechten (leicht nach außen).
	var arm_ab := {}
	for seite: Array in [[ARM_L, 1.0], [ARM_R, -1.0]]:
		var a: Vector3 = (g1[namen.find(seite[0][0])] as Transform3D).origin
		var h: Vector3 = (g1[namen.find(seite[0][1])] as Transform3D).origin
		var ziel_r := Vector3(float(seite[1]) * 0.06, -1.0, 0.0).normalized()
		arm_ab[namen.find(seite[0][0])] = Basis(Quaternion((h - a).normalized(), ziel_r))
	wurzel.free()
	return { "namen": namen, "eltern": eltern, "rest": rest, "global": g1, "reihe": _reihenfolge(eltern), "haut": neue_haut, "netze": netze,
		"textur": load(ORDNER + person + ".png") as Texture2D, "kopf_mitte": (lo + hi) * 0.5, "kopf_r": (hi - lo) * 0.5,
		"huefte": (g1[namen.find("Hips")] as Transform3D).origin.y, "arm_ab": arm_ab }


## Ein Teil als eigenes, kompaktes Netz (nur seine Ecken).
static func _netz(teil: PackedInt32Array, pos: PackedVector3Array, nor: PackedVector3Array, uv: PackedVector2Array, bo: PackedInt32Array,
		we: PackedFloat32Array, nb: int) -> ArrayMesh:
	var neu := {}
	var p2 := PackedVector3Array()
	var n2 := PackedVector3Array()
	var u2 := PackedVector2Array()
	var b2 := PackedInt32Array()
	var w2 := PackedFloat32Array()
	var i2 := PackedInt32Array()
	for alt in teil:
		if not neu.has(alt):
			neu[alt] = p2.size()
			p2.append(pos[alt])
			n2.append(nor[alt])
			u2.append(uv[alt])
			for j in nb:
				b2.append(bo[alt * nb + j])
				w2.append(we[alt * nb + j])
		i2.append(int(neu[alt]))
	var m := ArrayMesh.new()
	if i2.is_empty():
		return m
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = p2
	a[Mesh.ARRAY_NORMAL] = n2
	a[Mesh.ARRAY_TEX_UV] = u2
	a[Mesh.ARRAY_BONES] = b2
	a[Mesh.ARRAY_WEIGHTS] = w2
	a[Mesh.ARRAY_INDEX] = i2
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if nb == 8 else 0)
	return m


## Eltern vor Kindern.
static func _reihenfolge(eltern: Array) -> Array:
	var out: Array = []
	var drin := {}
	while out.size() < eltern.size():
		for i in eltern.size():
			if not drin.has(i) and (int(eltern[i]) < 0 or drin.has(int(eltern[i]))):
				out.append(i)
				drin[i] = true
	return out

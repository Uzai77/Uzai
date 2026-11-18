extends RefCounted
## QR-Code-Erzeuger (Byte-Modus, Version 1 bis 40), nach dem Verfahren von Project Nayuki.
## Von Anmelde-Adressen bis zu langen Adressen wie dem Fehlerbericht. encode() gibt ein Array
## aus Zeilen zurück, jede Zeile ein PackedByteArray mit 1 = dunkel.

const ECL_FORMAT := { "L": 1, "M": 0, "Q": 3, "H": 2 }
const ECL_INDEX := { "L": 0, "M": 1, "Q": 2, "H": 3 }
const ECC_PER_BLOCK := [
	[-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
		30],
	[-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
		28, 28],
	[-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
		30, 30],
	[-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
		30, 30],
]
const NUM_BLOCKS := [
	[-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
	[-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
	[-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
	[-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],
]
const MAX_VERSION := 40

var size := 0
var version := 0
var mask := 0
var _mod: Array = []    # [y][x] -> bool
var _fn: Array = []     # [y][x] -> bool (Funktionsmuster)


## text: Inhalt. ecl: L/M/Q/H. force_mask: -1 wählt die beste Maske selbst.
static func encode(text: String, ecl := "M", force_mask := -1, force_version := 0) -> Array:
	var q = load("res://src/core/qr.gd").new()
	if not q._build(text.to_utf8_buffer(), ecl, force_mask, force_version):
		return []
	var rows: Array = []
	for y in q.size:
		var r := PackedByteArray()
		r.resize(q.size)
		for x in q.size:
			r[x] = 1 if q._mod[y][x] else 0
		rows.append(r)
	return rows


static func _raw_modules(ver: int) -> int:
	var r := (16 * ver + 128) * ver + 64
	if ver >= 2:
		var na := ver / 7 + 2
		r -= (25 * na - 10) * na - 55
		if ver >= 7:
			r -= 36
	return r


static func _data_codewords(ver: int, ei: int) -> int:
	return _raw_modules(ver) / 8 - ECC_PER_BLOCK[ei][ver] * NUM_BLOCKS[ei][ver]


func _build(data: PackedByteArray, ecl: String, force_mask: int, force_version: int) -> bool:
	var ei: int = ECL_INDEX.get(ecl, 1)
	var ver := 0
	for v in range(1, MAX_VERSION + 1):
		if force_version > 0 and v != force_version:
			continue
		var cc_bits := 8 if v < 10 else 16
		if 4 + cc_bits + data.size() * 8 <= _data_codewords(v, ei) * 8:
			ver = v
			break
	if ver == 0:
		return false
	version = ver
	size = ver * 4 + 17
	# Bitfolge: Modus, Länge, Daten, Abschluss, Füllbytes
	var bits: Array = []
	_append_bits(bits, 0x4, 4)
	_append_bits(bits, data.size(), 8 if ver < 10 else 16)
	for b in data:
		_append_bits(bits, b, 8)
	var cap := _data_codewords(ver, ei) * 8
	_append_bits(bits, 0, mini(4, cap - bits.size()))
	_append_bits(bits, 0, (8 - bits.size() % 8) % 8)
	var pad := 0xEC
	while bits.size() < cap:
		_append_bits(bits, pad, 8)
		pad = 0x11 if pad == 0xEC else 0xEC
	var words := PackedByteArray()
	words.resize(bits.size() / 8)
	for i in bits.size():
		words[i >> 3] = words[i >> 3] | (bits[i] << (7 - (i & 7)))
	var all := _add_ecc(words, ei)
	_mod = []
	_fn = []
	for y in size:
		var r1: Array = []
		var r2: Array = []
		r1.resize(size)
		r2.resize(size)
		r1.fill(false)
		r2.fill(false)
		_mod.append(r1)
		_fn.append(r2)
	_draw_function_patterns(ecl)
	_draw_codewords(all)
	if force_mask >= 0:
		mask = force_mask
	else:
		var best := INF
		for m in 8:
			_apply_mask(m)
			_draw_format(ecl, m)
			var p := _penalty()
			if p < best:
				best = p
				mask = m
			_apply_mask(m)
	_apply_mask(mask)
	_draw_format(ecl, mask)
	return true


static func _append_bits(bits: Array, val: int, n: int) -> void:
	for i in range(n - 1, -1, -1):
		bits.append((val >> i) & 1)


func _add_ecc(data: PackedByteArray, ei: int) -> PackedByteArray:
	var nb: int = NUM_BLOCKS[ei][version]
	var ecc_len: int = ECC_PER_BLOCK[ei][version]
	var raw := _raw_modules(version) / 8
	var num_short := nb - raw % nb
	var short_len := raw / nb
	var div := _rs_divisor(ecc_len)
	var blocks: Array = []
	var k := 0
	for i in nb:
		var n := short_len - ecc_len + (0 if i < num_short else 1)
		var dat := data.slice(k, k + n)
		k += n
		var ecc := _rs_remainder(dat, div)
		if i < num_short:
			dat.append(0)
		dat.append_array(ecc)
		blocks.append(dat)
	var out := PackedByteArray()
	for i in (blocks[0] as PackedByteArray).size():
		for j in blocks.size():
			if i != short_len - ecc_len or j >= num_short:
				out.append(blocks[j][i])
	return out


static func _gf_mul(x: int, y: int) -> int:
	var z := 0
	for i in range(7, -1, -1):
		z = ((z << 1) ^ ((z >> 7) * 0x11D)) & 0xFF
		z ^= ((y >> i) & 1) * x
	return z


static func _rs_divisor(degree: int) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(degree)
	r.fill(0)
	r[degree - 1] = 1
	var root := 1
	for i in degree:
		for j in degree:
			r[j] = _gf_mul(r[j], root)
			if j + 1 < degree:
				r[j] ^= r[j + 1]
		root = _gf_mul(root, 0x02)
	return r


static func _rs_remainder(data: PackedByteArray, div: PackedByteArray) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(div.size())
	r.fill(0)
	for b in data:
		var factor := b ^ r[0]
		r.remove_at(0)
		r.append(0)
		for i in div.size():
			r[i] ^= _gf_mul(div[i], factor)
	return r


func _set_fn(x: int, y: int, dark: bool) -> void:
	_mod[y][x] = dark
	_fn[y][x] = true


func _draw_function_patterns(ecl: String) -> void:
	for i in size:
		_set_fn(6, i, i % 2 == 0)
		_set_fn(i, 6, i % 2 == 0)
	for c in [Vector2i(3, 3), Vector2i(size - 4, 3), Vector2i(3, size - 4)]:
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var xx: int = c.x + dx
				var yy: int = c.y + dy
				if xx >= 0 and xx < size and yy >= 0 and yy < size:
					var dist := maxi(absi(dx), absi(dy))
					_set_fn(xx, yy, dist != 2 and dist != 4)
	var pos := _align_positions()
	var n := pos.size()
	for i in n:
		for j in n:
			if (i == 0 and j == 0) or (i == 0 and j == n - 1) or (i == n - 1 and j == 0):
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					_set_fn(pos[i] + dx, pos[j] + dy, maxi(absi(dx), absi(dy)) != 1)
	_draw_format(ecl, 0)
	if version >= 7:
		var rem := version
		for i in 12:
			rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
		var bits := (version << 12) | rem
		for i in 18:
			var bit := ((bits >> i) & 1) != 0
			var a := size - 11 + i % 3
			var b := i / 3
			_set_fn(a, b, bit)
			_set_fn(b, a, bit)


func _align_positions() -> Array:
	if version == 1:
		return []
	var na := version / 7 + 2
	var step := (version * 8 + na * 3 + 5) / (na * 4 - 4) * 2
	var out: Array = []
	for i in na - 1:
		out.append(size - 7 - i * step)
	out.append(6)
	out.reverse()
	return out


func _draw_format(ecl: String, m: int) -> void:
	var dat: int = (ECL_FORMAT.get(ecl, 0) << 3) | m
	var rem := dat
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits := ((dat << 10) | rem) ^ 0x5412
	for i in range(0, 6):
		_set_fn(8, i, ((bits >> i) & 1) != 0)
	_set_fn(8, 7, ((bits >> 6) & 1) != 0)
	_set_fn(8, 8, ((bits >> 7) & 1) != 0)
	_set_fn(7, 8, ((bits >> 8) & 1) != 0)
	for i in range(9, 15):
		_set_fn(14 - i, 8, ((bits >> i) & 1) != 0)
	for i in range(0, 8):
		_set_fn(size - 1 - i, 8, ((bits >> i) & 1) != 0)
	for i in range(8, 15):
		_set_fn(8, size - 15 + i, ((bits >> i) & 1) != 0)
	_set_fn(8, size - 8, true)


func _draw_codewords(data: PackedByteArray) -> void:
	var i := 0
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := size - 1 - vert if upward else vert
				if not _fn[y][x] and i < data.size() * 8:
					_mod[y][x] = ((data[i >> 3] >> (7 - (i & 7))) & 1) != 0
					i += 1
		right -= 2


func _apply_mask(m: int) -> void:
	for y in size:
		for x in size:
			if _fn[y][x]:
				continue
			var inv := false
			match m:
				0: inv = (x + y) % 2 == 0
				1: inv = y % 2 == 0
				2: inv = x % 3 == 0
				3: inv = (x + y) % 3 == 0
				4: inv = (x / 3 + y / 2) % 2 == 0
				5: inv = x * y % 2 + x * y % 3 == 0
				6: inv = (x * y % 2 + x * y % 3) % 2 == 0
				7: inv = ((x + y) % 2 + x * y % 3) % 2 == 0
			if inv:
				_mod[y][x] = not _mod[y][x]


## Vereinfachte Bewertung (Läufe, 2×2-Blöcke, Hell-Dunkel-Verhältnis). Jede Maske ist
## gültig, diese hier wählt nur eine gut lesbare aus.
func _penalty() -> float:
	var p := 0
	for y in size:
		var run := 1
		for x in range(1, size + 1):
			if x < size and _mod[y][x] == _mod[y][x - 1]:
				run += 1
			else:
				if run >= 5:
					p += run - 2
				run = 1
	for x in size:
		var run := 1
		for y in range(1, size + 1):
			if y < size and _mod[y][x] == _mod[y - 1][x]:
				run += 1
			else:
				if run >= 5:
					p += run - 2
				run = 1
	var dark := 0
	for y in size:
		for x in size:
			if _mod[y][x]:
				dark += 1
			if x < size - 1 and y < size - 1:
				var c: bool = _mod[y][x]
				if _mod[y][x + 1] == c and _mod[y + 1][x] == c and _mod[y + 1][x + 1] == c:
					p += 3
	var total := size * size
	var k := int(ceil(absf(dark * 20.0 - total * 10.0) / total)) - 1
	p += maxi(0, k) * 10
	return float(p)

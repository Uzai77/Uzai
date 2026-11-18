extends RefCounted
## Gemeinsame Prüfungen für fremde Eingaben (Sicherheitsprüfung, Punkte 78/80; docs/SECURITY.md):
## Steam-Links aus Chats und vom Status eines Freundes, Pfade aus fremden Daten und Adressen, die
## Uzai selbst abruft, weil sie in fremden Daten standen (Link-Vorschau, Plugin-Skripte).

const MAX_HOPS := 4               ## Weiterleitungen, denen Uzai bei fremden Adressen folgt


## Steam-Link zum Mitspielen aus fremder Quelle: nur steam://joinlobby/<App>/<Lobby>[/<Steam-ID>]
## aus Ziffern und steam://connect/<Host>[:<Port>] ohne alles dahinter. Über weitere Teile (etwa ein
## „Passwort“ hinter dem Port) gelangten fremde Texte bis in die Startparameter des Spiels.
static func steam_join_ok(url: String) -> bool:
	var low := url.to_lower()
	if low.begins_with("steam://joinlobby/"):
		var parts := url.substr(18).split("/")
		if parts.size() < 2 or parts.size() > 3:
			return false
		for p in parts:
			if not _digits(p, 20):
				return false
		return true
	if low.begins_with("steam://connect/"):
		var hp := url.substr(16)
		var host := hp
		if hp.count(":") == 1:
			host = hp.get_slice(":", 0)
			if not _digits(hp.get_slice(":", 1), 5) or int(hp.get_slice(":", 1)) > 65535:
				return false
		if host == "" or host.length() > 253:
			return false
		for ch in host:
			if not ((ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "." or ch == "-"):
				return false
		return true
	return false


static func _digits(s: String, most: int) -> bool:
	if s == "" or s.length() > most:
		return false
	for ch in s:
		if ch < "0" or ch > "9":
			return false
	return true


## Pfad aus fremden Daten (Bildadresse eines Addons, Avatar …), den Uzai als Datei öffnen würde:
## nie eine Windows-Freigabe (\\server\…, //server/…, \\?\UNC\…, \??\UNC\…). Schon das Nachsehen, ob es
## die Datei gibt, schickte sonst die Windows-Anmeldung (NTLM) an einen fremden Rechner.
## „?“ und „*“ stehen in keinem Windows-Dateinamen: Mit „\??\“ reicht Windows den Rest als NT-Pfad durch
## (\??\UNC\server\…, \??\GLOBALROOT\Device\Mup\…) – auch ohne doppelten Schrägstrich am Anfang.
static func local_path_ok(p: String) -> bool:
	if p.length() < 2 or p.to_utf8_buffer().has(0) or p.contains("?") or p.contains("*"):
		return false
	return not ((p[0] == "/" or p[0] == "\\") and (p[1] == "/" or p[1] == "\\"))


## Rechner einer Windows-Freigabe („//nas/roms/…“ oder „\\nas\roms\…“), klein geschrieben; "" für alles andere (auch für
## NT-Pfade mit „?“/„*“).
static func freigabe_host(p: String) -> String:
	if p.length() < 3 or p.contains("?") or p.contains("*") or p.to_utf8_buffer().has(0):
		return ""
	var s := p.replace("\\", "/")
	if not s.begins_with("//") or s.begins_with("///"):
		return ""
	return s.substr(2).get_slice("/", 0).to_lower()


## Verweis aus einer Liste (.cue/.gdi/.m3u): lokal, oder auf demselben Rechner wie die Liste selbst. Liegt die Sammlung
## auf einem NAS, gehen die Verweise dorthin – dahin spricht Windows ohnehin schon; ein anderer Rechner nie.
static func verweis_ok(ref: String, liste: String) -> bool:
	if local_path_ok(ref):
		return true
	var h := freigabe_host(ref)
	return h != "" and h == freigabe_host(liste)


## Darf Uzai diese Datei eines anderen Programms anfassen (lesen und zurückschreiben)? Bekannter Name (klein
## geschrieben in namen), lokal und absolut, kein „..“ oder „.“, unter einem der Ordner in roots (je mehr als ein
## Laufwerk), vorhanden und höchstens max_bytes groß. Für Pfade aus gemerkten Daten (Einstellungen, Sicherungen),
## die eine fremde Datei sonst auf beliebige Ziele lenken könnte.
static func datei_unter(path: String, roots: Array, namen: Array, max_bytes: int) -> bool:
	var p := path.replace("\\", "/")
	if not local_path_ok(p) or p.contains("/../") or p.ends_with("/..") or p.contains("/./") or not p.get_file().to_lower() in namen:
		return false
	if not (p.length() > 2 and p[1] == ":") and not p.begins_with("/"):
		return false
	var drin := false
	for r in roots:
		var rr := str(r).replace("\\", "/").trim_suffix("/")
		if rr.length() > 3 and p.to_lower().begins_with(rr.to_lower() + "/"):
			drin = true
	if not drin or not FileAccess.file_exists(p):
		return false
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return false
	var n := f.get_length()
	f.close()
	return n > 0 and n <= max_bytes


## IP-Adresse, die nicht ins Internet gehört: dieser PC, Heimnetz, Link-local, CGNAT, Test-,
## Multicast- und reservierte Bereiche; IPv6 Loopback, unbestimmt, ULA, Link-local, Multicast,
## NAT64 und IPv4 in IPv6. Keine gültige Adresse zählt ebenfalls als gesperrt.
static func ip_blocked(ip: String) -> bool:
	var a := ip.strip_edges().to_lower().trim_prefix("[").trim_suffix("]")
	if a.contains("%"):
		return true
	if not a.is_valid_ip_address():
		return true
	if not a.contains(":"):
		var p := a.split(".")
		# Führende Null: Godot liest „012“ als 12, andere Programme und Browser als oktal (10). Was zwei Lesarten
		# hat, gilt als gesperrt.
		for teil in p:
			if teil.length() > 1 and teil.begins_with("0"):
				return true
		var b0 := int(p[0])
		var b1 := int(p[1])
		var b2 := int(p[2])
		return b0 == 0 or b0 == 10 or b0 == 127 or b0 >= 224 or (b0 == 169 and b1 == 254) \
			or (b0 == 172 and b1 >= 16 and b1 <= 31) or (b0 == 192 and b1 == 168) \
			or (b0 == 100 and b1 >= 64 and b1 <= 127) or (b0 == 192 and b1 == 0 and b2 == 0) \
			or (b0 == 198 and (b1 == 18 or b1 == 19))
	var g := _ipv6_groups(a)
	if g.size() != 8:
		return true
	var head_zero := g[0] == 0 and g[1] == 0 and g[2] == 0 and g[3] == 0 and g[4] == 0
	if head_zero and (g[5] == 0 or g[5] == 0xffff):
		return true                                        # ::, ::1, ::a.b.c.d, ::ffff:a.b.c.d
	if g[0] == 0x64 and g[1] == 0xff9b:
		return true                                        # NAT64
	return (g[0] & 0xfe00) == 0xfc00 or (g[0] & 0xffc0) == 0xfe80 or (g[0] & 0xff00) == 0xff00


## Die acht 16-Bit-Gruppen einer IPv6-Adresse (auch mit „::“ und IPv4 am Ende); [] wenn ungültig.
static func _ipv6_groups(a: String) -> PackedInt32Array:
	var s := a
	var tail := PackedInt32Array()
	var last := s.get_slice(":", s.get_slice_count(":") - 1)
	if last.contains("."):
		if not last.is_valid_ip_address():
			return PackedInt32Array()
		var q := last.split(".")
		tail = PackedInt32Array([(int(q[0]) << 8) | int(q[1]), (int(q[2]) << 8) | int(q[3])])
		s = s.left(s.length() - last.length())
		if s.ends_with(":") and not s.ends_with("::"):
			s = s.left(-1)
	var halves := s.split("::")
	if halves.size() > 2:
		return PackedInt32Array()
	var front := PackedInt32Array()
	var back := PackedInt32Array()
	for i in halves.size():
		if halves[i] == "":
			continue
		for part in halves[i].split(":"):
			if part == "" or part.length() > 4 or not part.is_valid_hex_number():
				return PackedInt32Array()
			if i == 0:
				front.append(part.hex_to_int())
			else:
				back.append(part.hex_to_int())
	back.append_array(tail)
	var missing := 8 - front.size() - back.size()
	if missing < 0 or (halves.size() == 1 and missing != 0):
		return PackedInt32Array()
	var out := front.duplicate()
	for i in missing:
		out.append(0)
	out.append_array(back)
	return out


## Schema und Host einer Adresse ("" wenn sie nicht passt). Benutzer und Passwort vor „@“ fallen
## weg; IPv6 bleibt in eckigen Klammern.
static func url_parts(url: String) -> Dictionary:
	var u := url.strip_edges()
	var i := u.find("://")
	if i <= 0:
		return {}
	var scheme := u.left(i).to_lower()
	var rest := u.substr(i + 3)
	var auth := rest
	for sep in ["/", "?", "#", "\\"]:
		auth = auth.get_slice(sep, 0)
	if auth.contains("@"):
		auth = auth.get_slice("@", auth.count("@"))
	var host := auth
	var port := ""
	if auth.begins_with("["):
		var close := auth.find("]")
		if close < 0:
			return {}
		host = auth.substr(1, close - 1)
		port = auth.substr(close + 1).trim_prefix(":")
	elif auth.count(":") == 1:
		host = auth.get_slice(":", 0)
		port = auth.get_slice(":", 1)
	elif auth.count(":") > 1:
		return {}
	if host == "" or (port != "" and not _digits(port, 5)):
		return {}
	return { "scheme": scheme, "host": host.to_lower(), "port": port }


## Darf Uzai eine Adresse aus fremden Daten selbst abrufen? Nur http(s) (https_only: nur https)
## und nie zu diesem PC oder ins Heimnetz – auch nicht über einen Namen, der dorthin zeigt (alle
## Adressen der Namensauflösung müssen ins Internet gehen). resolve = false prüft nur, was in der
## Adresse selbst steht.
static func public_url_ok(url: String, https_only := false, resolve := true) -> bool:
	var p := url_parts(url)
	if p.is_empty() or not (p.scheme == "https" or (p.scheme == "http" and not https_only)):
		return false
	var host := str(p.host).trim_suffix(".")
	if host == "localhost" or host.ends_with(".localhost") or host.ends_with(".local") or host.ends_with(".internal") or host.ends_with(".home.arpa"):
		return false
	if host.is_valid_ip_address() or host.contains(":"):
		return not ip_blocked(host)
	# Zahlen-Schreibweisen von IPv4 (2130706433, 0x7f.1, 127.1) lösen Windows und Godot zu
	# Adressen auf – ohne Buchstaben außer Hex ist das kein Name.
	if _numeric_host(host):
		return false
	if not resolve:
		return true
	var addrs := IP.resolve_hostname_addresses(host, IP.TYPE_ANY)
	if addrs.is_empty():
		return false
	for a in addrs:
		if ip_blocked(str(a)):
			return false
	return true


## Wie public_url_ok, aber die Namensauflösung blockiert nie das Bild (höchstens 5 s, dann nein).
static func public_url_async(url: String, https_only := false) -> bool:
	if not public_url_ok(url, https_only, false):
		return false
	var host := str(url_parts(url).host).trim_suffix(".")
	if host.is_valid_ip_address() or host.contains(":"):
		return true
	var addrs := await adressen_von(host)
	if addrs.is_empty():
		return false
	for a in addrs:
		if ip_blocked(str(a)):
			return false
	return true


## Alle Adressen zu einem Namen, ohne das Bild anzuhalten (höchstens 5 s, dann leer). Die einfache Abfrage
## IP.resolve_hostname_addresses wartet im Hauptfaden – bei einem Namen, den niemand kennt, sekundenlang.
static func adressen_von(host: String) -> Array:
	var id := IP.resolve_hostname_queue_item(host, IP.TYPE_ANY)
	if id == IP.RESOLVER_INVALID_ID:
		return []
	var tree := Engine.get_main_loop() as SceneTree
	var until := Time.get_ticks_msec() + 5000
	while IP.get_resolve_item_status(id) == IP.RESOLVER_STATUS_WAITING and Time.get_ticks_msec() < until and tree != null:
		await tree.process_frame
	var addrs: Array = IP.get_resolve_item_addresses(id) if IP.get_resolve_item_status(id) == IP.RESOLVER_STATUS_DONE else []
	IP.erase_resolve_item(id)
	return addrs


static func _numeric_host(h: String) -> bool:
	for label in h.split("."):
		if label == "":
			continue
		var l := label.to_lower()
		if not (_digits(l, 64) or (l.begins_with("0x") and (l.length() == 2 or l.substr(2).is_valid_hex_number()))):
			return false
	return true


## Ziel einer Weiterleitung (Kopfzeile „Location“) relativ zur bisherigen Adresse; "" wenn es keins gibt.
static func redirect_target(base: String, location: String) -> String:
	var loc := location.strip_edges()
	if loc == "":
		return ""
	if loc.find("://") > 0:
		return loc
	var p := url_parts(base)
	if p.is_empty():
		return ""
	var origin := "%s://%s%s" % [p.scheme, ("[%s]" % p.host) if str(p.host).contains(":") else str(p.host), (":" + str(p.port)) if str(p.port) != "" else ""]
	if loc.begins_with("//"):
		return str(p.scheme) + ":" + loc
	if loc.begins_with("/"):
		return origin + loc
	var path := base.substr(base.find("://") + 3)
	var slash := path.find("/")
	var dir := path.substr(slash).get_slice("?", 0).get_slice("#", 0).get_base_dir() if slash >= 0 else ""
	return origin + dir.trim_suffix("/") + "/" + loc


## Gleicher Ursprung (Schema, Host, Anschluss)?
static func same_origin(a: String, b: String) -> bool:
	var pa := url_parts(a)
	var pb := url_parts(b)
	return not pa.is_empty() and pa == pb


## Geheimnisse vergleichen, ohne dass die Dauer verrät, ab welcher Stelle sie abweichen.
static func same_secret(a: String, b: String) -> bool:
	var x := a.to_utf8_buffer()
	var y := b.to_utf8_buffer()
	if x.size() != y.size() or x.is_empty():
		return false
	return Crypto.new().constant_time_compare(x, y)

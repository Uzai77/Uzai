extends RefCounted
## Shop, Reihen und Bühne: reine Funktionen ohne Netz und ohne Oberfläche – welche Spiele auf die
## Bühne kommen, welcher Grund dort steht („Angebot · endet in 5 Std.“, „Mira spielt gerade“),
## welche Spiele deiner Freunde eine Reihe bilden und wohin alte Unterbereiche führen.
## Geprüft in tests/logic_shop_reihen.gd; shop_view.gd und shop_buehne.gd rufen nur auf.

const Lang := preload("res://src/core/lang.gd")

## Alte Unterbereiche des Shops → heutiger Unterbereich und Ort darin (Liste bzw. Genre-Seite).
const ALTE_SUBS := {
	"gratis": ["specials", ""], "top_sellers": ["entdecken", "top_sellers"], "new_releases": ["entdecken", "new_releases"],
	"coming_soon": ["entdecken", "coming_soon"], "genres": ["entdecken", ""], "angebote": ["specials", ""],
}

## Listen, die als Ort aus einer Reihe heraus ganz zu sehen sind: Schlüssel → Überschrift.
const LISTEN := { "top_sellers": "Topseller", "new_releases": "Neu", "coming_soon": "Bald", "f2p": "Kostenlos spielbar", "retro": "Retro-Klassiker" }


## Übersetzter Text als String (TranslationServer liefert StringName; Vergleiche und % brauchen String).
static func _t(key: String) -> String:
	return str(TranslationServer.translate(key))


## Wohin ein Unterbereich führt: [sub, liste]. Heutige Namen bleiben, wie sie sind.
static func ziel(sub_id: String) -> Array:
	if ALTE_SUBS.has(sub_id):
		return (ALTE_SUBS[sub_id] as Array).duplicate()
	return [sub_id, ""]


## Kennung eines Eintrags: App-ID, sonst die eigene Kennung (Gratis-Spiele von Epic).
static func key_of(it: Dictionary) -> String:
	var id := int(it.get("appid", 0))
	return str(id) if id > 0 else str(it.get("id", it.get("name", "")))


static func _owned(it: Dictionary, owned: Dictionary) -> bool:
	return int(it.get("appid", 0)) > 0 and owned.has(int(it.appid))


## Die Spiele der Bühne (höchstens n), gemischt: der größte Rabatt zuerst, dann ein Spiel, das
## deine Freunde gerade spielen, ein Gratis-Spiel, das neueste Spiel – danach weitere Rabatte und
## Topseller. Nichts doppelt, nichts aus deiner Bibliothek (nur wenn sonst zu wenig bleibt).
static func buehne(specials: Array, top: Array, neu: Array, gratis: Array, freunde: Array, owned: Dictionary, n := 6) -> Array:
	var out: Array = []
	var seen := {}
	var nimm := func(it: Variant) -> bool:
		if not (it is Dictionary) or out.size() >= n:
			return false
		var k := key_of(it)
		if k == "" or seen.has(k) or _owned(it, owned):
			return false
		seen[k] = true
		out.append(it)
		return true
	var rabatte: Array = (specials + top).filter(func(x: Variant) -> bool: return x is Dictionary and int(x.get("discount", 0)) > 0 and int(x.get("price", 0)) > 0)
	rabatte.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.discount) > int(b.discount))
	for r0 in rabatte:
		if nimm.call(r0):
			break
	for f in freunde:
		if nimm.call(f):
			break
	for g in gratis:
		if nimm.call(g):
			break
	for x in neu:
		if nimm.call(x):
			break
	for r in rabatte:
		nimm.call(r)
	for t in top:
		nimm.call(t)
	# Zu wenig (fast alles gehört dir): dann auch Spiele aus der Bibliothek, damit die Bühne nicht leer ist.
	if out.size() < 2:
		for t in rabatte + top:
			if out.size() >= n:
				break
			var k := key_of(t)
			if t is Dictionary and k != "" and not seen.has(k):
				seen[k] = true
				out.append(t)
	return out


## Die Spiele, die Steam-Freunde gerade spielen (App-IDs, jede einmal, in der Reihenfolge der Liste).
static func freunde_ids(friends: Array) -> Array:
	var out: Array = []
	for f in friends:
		if not (f is Dictionary):
			continue
		var gid := str(f.get("game_id", ""))
		if gid.is_valid_int() and int(gid) > 0 and str(f.get("game", "")) != "" and not out.has(int(gid)):
			out.append(int(gid))
	return out


## Namen der Freunde, die dieses Spiel gerade spielen.
static func freunde_namen(friends: Array, appid: int) -> Array:
	var out: Array = []
	if appid <= 0:
		return out
	for f in friends:
		if f is Dictionary and str(f.get("game_id", "")) == str(appid) and str(f.get("name", "")) != "":
			out.append(str(f.name))
	return out


## „Mira spielt gerade“, „Mira und Noor spielen gerade“, „3 Freunde spielen gerade“.
static func freunde_text(namen: Array) -> String:
	match namen.size():
		0: return ""
		1: return _t("%s spielt gerade") % str(namen[0])
		2: return _t("%s spielen gerade") % (_t("%s und %s") % [str(namen[0]), str(namen[1])])
	return _t("%d Freunde spielen gerade") % namen.size()


## Die Spiele der Freunde als Reihe: erst, was du nicht hast, dann der Rest – in der Reihenfolge
## der Freundesliste (wer online ist, steht dort vorn).
static func freunde_reihe(items: Array, friends: Array, owned: Dictionary) -> Array:
	var ids := freunde_ids(friends)
	var by_id := {}
	for it in items:
		if it is Dictionary and int(it.get("appid", 0)) > 0:
			by_id[int(it.appid)] = it
	var fremd: Array = []
	var meins: Array = []
	for id in ids:
		if not by_id.has(id):
			continue
		if owned.has(id):
			meins.append(by_id[id])
		else:
			fremd.append(by_id[id])
	return fremd + meins


## „endet in 5 Std.“ bzw. „bis 2. Nov.“ – leer ohne Frist oder wenn sie vorbei ist.
static func frist(until: int, now: int) -> String:
	var left := until - now
	if until <= 0 or left <= 0:
		return ""
	if left < 86400 * 2:
		return _t("endet in %d Std.") % maxi(1, int(left / 3600.0))
	return _t("bis %s") % tag_text(until)


## „30. Okt.“ (Ortszeit, in der Sprache von Uzai).
static func tag_text(unix: int) -> String:
	if unix <= 0:
		return ""
	var d := Time.get_date_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	return Lang.date_text(int(d.day), int(d.month), 0, true)


## Der Grund, warum ein Spiel auf der Bühne steht, als höchstens zwei Teile (Versalien-Etikett):
## „Angebot“ + Frist, „Gratis“ + Frist, „Bald erhältlich“, „Neu“, „Kostenlos spielbar“, sonst
## „Topseller“; dazu, wer es gerade spielt – oder dass es auf deiner Wunschliste steht.
## ctx: { owned: bool, freunde: [Namen], neu: bool, wunsch: bool, now: int }
static func grund(it: Dictionary, ctx: Dictionary) -> Array:
	var now := int(ctx.get("now", Time.get_unix_time_from_system()))
	var teile: Array = []
	if bool(ctx.get("owned", false)):
		teile.append(_t("In deiner Bibliothek"))
	elif bool(it.get("giveaway", false)):
		if bool(it.get("upcoming", false)):
			teile.append(_t("Ab %s gratis") % tag_text(int(it.get("from", 0))))
		else:
			teile.append(_t("Gratis"))
			var fr := frist(int(it.get("until", 0)), now)
			if fr != "":
				teile.append(fr)
	elif int(it.get("discount", 0)) > 0 and int(it.get("price", 0)) > 0:
		teile.append(_t("Angebot"))
		var fr2 := frist(int(it.get("until", 0)), now)
		if fr2 != "":
			teile.append(fr2)
	elif bool(it.get("coming", false)):
		teile.append(_t("Bald erhältlich"))
	elif bool(ctx.get("neu", false)):
		teile.append(_t("Neu"))
	elif bool(it.get("free", false)):
		teile.append(_t("Kostenlos spielbar"))
	else:
		teile.append(_t("Topseller"))
	if teile.size() < 2:
		var ft := freunde_text(ctx.get("freunde", []))
		if ft != "":
			teile.append(ft)
		elif bool(ctx.get("wunsch", false)) and not bool(ctx.get("owned", false)):
			teile.append(_t("Auf deiner Wunschliste"))
	return teile


## Spiele unter einem Preis (Cent), die du nicht hast, günstigste zuerst – ab drei lohnt die Reihe.
static func unter_preis(items: Array, owned: Dictionary, cents := 1000) -> Array:
	var out: Array = items.filter(func(x: Variant) -> bool:
		return x is Dictionary and int(x.get("price", 0)) > 0 and int(x.get("price", 0)) <= cents and not _owned(x, owned))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.price) < int(b.price))
	return out if out.size() >= 3 else []

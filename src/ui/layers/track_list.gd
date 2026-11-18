extends "res://src/ui/layers/layer.gd"
## Eine Playlist, ein Album oder ein Mix mit allen Titeln (Aufbau: components/track_page.gd).
## Links groß das Bild mit Name, Angaben und „Abspielen“, rechts die Titel. A spielt ab diesem
## Titel (die Liste läuft danach weiter), X stellt ihn in die Warteschlange, Y markiert ihn als
## Lieblingssong. Mixe von Spotify und fremde Playlists geben eigenen Apps keine Titel heraus: dann
## steht das dort ehrlich, abspielen geht trotzdem. Wie die Spotify-App angemeldet kommen sie mit Titeln.

const TrackPage := preload("res://src/ui/components/track_page.gd")
const MusicTile := preload("res://src/ui/components/music_tile.gd")

var playlist: Dictionary = {}     ## { kind?, id, name, uri, count, art, owner, … } (Playlist, Album, Mix)
const Main := preload("res://src/main.gd")
var main: Main
var _page: Control


func build() -> void:
	dim = 1.0
	_scrim.color = Color(UzTheme.col("bg"), dim)
	set_meta("uz_hint_b", "Zurück")
	var info := info_for(playlist)
	# Ein weiter, ganz leiser Schein in der Farbe der Liste (oben links, wie Licht aus dem Bild).
	var amb := TextureRect.new()
	amb.texture = MusicTile.glow_tex()
	amb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	amb.stretch_mode = TextureRect.STRETCH_SCALE
	amb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amb.position = Vector2(-520, -560)
	amb.size = Vector2(1700, 1400)
	amb.modulate = Color(Color.from_hsv(float(info.get("hue", 0.6)), 0.5, 0.6), 0.16)
	add_child(amb)
	_page = TrackPage.new()
	_page.info = info
	_page.loader = loader_for(playlist)
	_page.group = "tracks"
	U.full_rect(_page)
	add_child(_page)


## Angaben für den Kopf der Liste je nach Art.
static func info_for(p: Dictionary) -> Dictionary:
	var info: Dictionary = p.duplicate()
	var kind := str(p.get("kind", "playlist"))
	info["kind"] = kind
	if not info.has("hue"):
		info["hue"] = float(absi(str(p.get("name", "")).hash()) % 1000) / 1000.0
	match kind:
		"album":
			var year := str(p.get("date", "")).get_slice("-", 0)
			info["kicker"] = ("Single" if str(p.get("type", "")) == "single" else "Album") + ((" · " + year) if year != "" else "")
			info["sub"] = str(p.get("artist", ""))
		"mix":
			info["kicker"] = "Mix aus deinen Hördaten"
			info["tile_kicker"] = "Mix"
			if str(p.get("id", "")) == "mix:neu":
				info["count"] = 0
		"spotify_mix":
			info["kicker"] = "Von Spotify · " + str(p.get("sub", ""))
			info["tile_kicker"] = "Spotify"
			if not Music.mix_titles():
				info["restricted"] = true
				info["restricted_text"] = "Spotify gibt die Titel dieser Mixe nicht an eigene Apps heraus. Mit der QR-Anmeldung erscheinen alle Titel."
		"liked":
			info["kicker"] = "Deine Bibliothek"
			info["icon"] = "heart_f"
		"recent":
			info["kicker"] = "Deine letzten Titel"
			info["icon"] = "history"
		"lokal_titel":
			info["kicker"] = "Eigene Musik"
		"lokal_interpret":
			info["kicker"] = "Interpret · %s" % U.plural((p.get("albums", []) as Array).size(), "Album", "Alben")
			info["icon"] = "user"
		_:
			var owner := str(p.get("owner", ""))
			info["kicker"] = "Playlist" + ((" · von " + owner) if owner != "" else "")
	return info


## Woher die Titel kommen (mit await aufrufen). Mixe von Spotify: nur wie die Spotify-App.
static func loader_for(p: Dictionary) -> Callable:
	var kind := str(p.get("kind", "playlist"))
	if bool(p.get("local", false)):
		return Callable()          # eigene Musik: die Titel liegen schon bei
	match kind:
		"album":
			return func() -> Array: return await Music.album_tracks(p)
		"mix":
			var mid := str(p.get("id", ""))
			return func() -> Array: return await Music.mix_tracks(mid)
		"spotify_mix":
			if not Music.mix_titles():
				return Callable()
		"liked", "recent":
			return Callable()
	var pid := str(p.get("id", ""))
	return func() -> Array: return await Music.playlist_tracks(pid)

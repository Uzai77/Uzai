// Draußen vor dem Fenster: Himmel nach Tageszeit, Sonne bzw. Mond, weiche Wolken, zwei Reihen
// ferner Hügel mit Bäumen als Silhouette (Luftperspektive), davor eine Wiese mit Kiesstreifen am
// Haus, nachts ein paar Sterne. Gerechnet nach der Blickrichtung (wie ein Himmel der Engine): Die
// Fläche dahinter ist eine große Kugel um das Fenster (raum.gd _fenster), von jedem Platz und in jeder
// Richtung – auch steil nach unten – liegt draußen etwas, nie das Schwarz dahinter. Die Wiese liegt
// wirklich auf boden_y (Strahl trifft Ebene), Himmel und Hügel sind unendlich weit.
// Feine Muster (Sterne, Gras, Kanten) nur so fein, wie ein Bildpunkt sie auflöst – sonst flimmern sie.
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled, shadows_disabled;

#include "res://src/room/shaders/rauschen.gdshaderinc"

uniform vec3 oben : source_color = vec3(0.35, 0.55, 0.85);
uniform vec3 horizont : source_color = vec3(0.85, 0.88, 0.92);
uniform vec3 sonne_farbe : source_color = vec3(1.0, 0.95, 0.85);
// Sonne bzw. Mond: Richtung (Bogenmaß) – x seitlich zur Fensternormale, y Höhe über dem Horizont.
uniform vec2 sonne = vec2(0.2, 0.3);
uniform float sonne_groesse = 0.035;
uniform vec3 huegel_nah : source_color = vec3(0.25, 0.33, 0.25);
uniform vec3 huegel_fern : source_color = vec3(0.45, 0.55, 0.6);
uniform float nacht = 0.0;
uniform float wolken = 0.5;
uniform float hell = 1.0;
uniform float boden_y = -0.3;      // Höhe der Wiese draußen (Weltkoordinaten)

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Blickrichtung → Winkel: seitlich (0 = gerade hinaus, das Fenster schaut nach -x) und Höhe.
vec2 winkel(vec3 d) {
	return vec2(atan(d.z, -d.x), asin(clamp(d.y, -1.0, 1.0)));
}

void fragment() {
	vec3 d = normalize(wp - CAMERA_POSITION_WORLD);
	vec2 a = winkel(d);
	float u = 0.5 + a.x / 2.2;
	float fw = max(fwidth(a.y), 0.0005);
	// Himmel: Verlauf, Sonne bzw. Mond mit Schein, Wolkenband, Sterne.
	vec3 c = mix(horizont, oben, smoothstep(0.0, 0.75, a.y));
	vec3 s = vec3(-cos(sonne.y) * cos(sonne.x), sin(sonne.y), cos(sonne.y) * sin(sonne.x));
	float ds = acos(clamp(dot(d, s), -1.0, 1.0));
	c += sonne_farbe * (1.0 - smoothstep(sonne_groesse - fw, sonne_groesse + fw, ds)) * 2.5;
	c += sonne_farbe * exp(-ds * 4.0) * 0.45;
	float w = uz_fbm2(vec2(a.x * 1.4, a.y * 4.4) + vec2(1.3, 0.0));
	float wl = smoothstep(0.52, 0.8, w) * smoothstep(0.04, 0.35, a.y) * wolken;
	c = mix(c, mix(horizont, sonne_farbe, 0.35) * 1.05, wl * 0.6);
	if (nacht > 0.0) {
		// Sterne: runde Punkte in einem Raster der Winkel (je Zelle höchstens einer), mindestens etwa
		// einen Bildpunkt groß – kleiner flimmerten sie bei jeder Bewegung.
		vec2 zg = a * 90.0;
		vec2 g = floor(zg);
		vec2 f = fract(zg) - 0.5;
		float da = uz_hash2(g);
		float zfw = max(fwidth(zg.x), fwidth(zg.y));
		float r = max(0.12, zfw * 0.8);
		float st = step(0.975, da) * (1.0 - smoothstep(r - zfw * 0.5, r + zfw * 0.5, length(f))) * smoothstep(0.06, 0.3, a.y);
		c += vec3(st) * nacht * (0.45 + 0.55 * fract(da * 97.0)) * clamp(0.12 / r, 0.3, 1.0);
	}
	// Hügel: fern (blasser) und nah mit Baumkronen.
	float h1 = 0.05 + 0.03 * sin(u * 5.1 + 1.0) + 0.02 * uz_noise2(vec2(u * 9.0, 0.0));
	float h2 = 0.016 + 0.022 * sin(u * 3.3 + 2.4) + 0.035 * uz_noise2(vec2(u * 22.0, 3.0)) * step(0.5, uz_noise2(vec2(u * 4.0, 1.0)));
	c = mix(c, mix(huegel_fern, horizont, 0.35), 1.0 - smoothstep(h1 - fw, h1 + fw, a.y));
	c = mix(c, huegel_nah, 1.0 - smoothstep(h2 - fw, h2 + fw, a.y));
	// Unter dem Horizont: die Wiese, wo der Blick die Ebene boden_y trifft; in der Ferne geht sie in
	// die Farbe der nahen Hügel über (deren Fuß).
	if (d.y < -0.0005 && CAMERA_POSITION_WORLD.y > boden_y) {
		float t = (boden_y - CAMERA_POSITION_WORLD.y) / d.y;
		vec3 p = CAMERA_POSITION_WORLD + d * t;
		vec2 pfw = fwidth(p.xz);
		float scharf = 1.0 - smoothstep(0.15, 0.6, max(pfw.x, pfw.y));
		float grob = uz_noise2(p.xz * 0.22);
		float fein = uz_noise2(p.xz * 2.3) * scharf;
		// Gemähte Bahnen (breit, nur wo ein Bildpunkt sie auflöst) und Flecken: eine Wiese, kein Teppich.
		float bahnen = (0.5 + 0.5 * sin(p.z * 1.4)) * (1.0 - smoothstep(0.3, 0.9, pfw.y * 1.4));
		vec3 wiese = huegel_nah * (0.82 + 0.45 * grob + 0.14 * (fein - 0.5 * scharf) + 0.08 * bahnen);
		// Kies am Haus, mit weichem Übergang zur Wiese.
		float kies = smoothstep(-0.95, -0.75, p.x);
		vec3 grau = mix(huegel_nah, horizont, 0.55) * 0.72;
		wiese = mix(wiese, grau * (0.92 + 0.16 * fein), kies);
		float ferne = 1.0 - exp(-t / 70.0);
		wiese = mix(wiese, huegel_nah, ferne);
		c = mix(c, wiese, 1.0 - smoothstep(-fw * 2.0, 0.0, a.y));
	}
	ALBEDO = c * hell;
}

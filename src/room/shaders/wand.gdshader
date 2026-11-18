// Wände und Decke: echte Oberflächen aus Karten (Albedo, Normal, Rauheit – stoffe.gd TEXTUREN) auf
// Wandkoordinaten (Meter entlang der Wand, Höhe), die Farbe des Nutzers tönt die Karte um ihren
// Mittelwert. Die Arten (gestalt.gd WANDMATERIAL) legen Fugen, Bretter, Ziegel und Fliesen als
// Muster darüber. Im Kompatibilitäts-Renderer rechnen die Lampen hier im Shader
// (lichter.gdshaderinc) und eine kleine Umgebungsverdeckung in Ecken (eigen_ao); in Forward+ kommt
// das Licht aus den gebackenen Lichtkarten (lichtbacken.gd: uz_lm, beim Backen weiß und matt), bis
// dahin von den Kopien der Lichter. Glanz nur aus Reflexionssonde und Himmel (specular_disabled: die
// Lampen spiegeln sich über die Sonde, kein Glanzpunkt je Lampe und Bildpunkt).
shader_type spatial;
render_mode diffuse_burley, specular_disabled;

#include "res://src/room/shaders/rauschen.gdshaderinc"
#include "res://src/room/shaders/lichter.gdshaderinc"
#include "res://src/room/shaders/muster.gdshaderinc"

uniform vec3 farbe : source_color = vec3(0.91, 0.88, 0.82);
uniform vec3 paneel_farbe : source_color = vec3(0.5, 0.56, 0.45);
uniform float paneel = 0.0;
uniform float paneel_hoehe = 1.05;
uniform vec2 raum = vec2(6.0, 5.0);
uniform float hoehe = 2.7;
uniform float eigen = 0.0;    // etwas Eigenlicht (Decke: Ersatz für Licht, das vom Boden zurückkommt)
uniform float eigen_ao = 1.0; // gerechnete Verdunklung zu Boden, Decke und Ecken (nur Kompatibilität)
// Anpassen (gestalt.gd, WANDMATERIAL): 0 Anstrich, 1 Kalkputz, 2 Tapete, 3 Paneel halbhoch,
// 4 Holzverkleidung, 5 Ziegel, 6 Sichtbeton, 7 Fliesen. Tapete mit Muster in muster_farbe.
uniform int art = 0;
uniform int muster = 0;
uniform vec3 muster_farbe : source_color = vec3(0.8, 0.74, 0.64);
// Karten der Oberfläche (stoffe.gd setzt sie je Art): Farbe, Normale, Rauheit; Kachelmaß in Metern.
uniform sampler2D t_farbe : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_rau : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 t_mass = vec2(1.0, 1.0);
uniform vec3 t_mittel : source_color = vec3(0.84, 0.84, 0.84);
uniform float t_rau_mittel = 0.86;
uniform float t_staerke = 1.0;
uniform float t_farbe_an = 1.0;   // 1: die Karte trägt die Farbe (getönt), 0: nur ihre Helligkeit

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	bool decke = abs(wn.y) > 0.5;
	float entlang = abs(wn.z) > 0.5 ? wp.x : wp.z;
	float ecke = abs(wn.z) > 0.5 ? min(wp.x, raum.x - wp.x) : min(wp.z, raum.y - wp.z);
	vec2 pp = decke ? wp.xz : vec2(entlang, wp.y);
	vec2 tuv = pp / t_mass;
	vec3 tex = texture(t_farbe, tuv).rgb;
	float trau = texture(t_rau, tuv).r / max(t_rau_mittel, 0.05);
	// Karte um ihren Mittelwert getönt – die gewählte Farbe bleibt der Durchschnitt.
	vec3 getoent = farbe * tex / max(t_mittel, vec3(0.02));
	float hellig = dot(tex / max(t_mittel, vec3(0.02)), vec3(0.333));
	vec3 grund = mix(farbe * hellig, getoent, t_farbe_an);
	float putz = uz_fbm2(pp * 3.1) * 0.6 + uz_noise2(pp * 41.0) * 0.4;
	vec3 c = grund * (0.985 + 0.03 * putz);
	float rau = 0.88 * trau;
	float spec = 0.25;
	float nstaerke = t_staerke;
	if (art == 1) {
		float k = uz_fbm2(pp * 1.7 + 4.0);
		c = grund * (0.92 + 0.12 * k + 0.04 * putz);
		rau = 0.95 * trau;
	} else if (art == 2) {
		float m = muster > 0 ? uz_muster(pp, muster, 1.0) : 0.0;
		c = mix(farbe, muster_farbe, m) * (0.975 + 0.03 * uz_noise2(pp * 90.0)) * mix(1.0, hellig, 0.35);
		// Bahnen: ganz feine Stöße alle 53 cm.
		c *= mix(0.94, 1.0, uz_band(entlang / 0.53 + 0.5, 0.995));
		rau = 0.8;
		nstaerke *= 0.3;
	} else if (art == 4) {
		float brett = fract(entlang / 0.12);
		float id = uz_hash2(vec2(floor(entlang / 0.12), 2.0));
		c = grund * (0.88 + 0.12 * id) * mix(0.55, 1.0, smoothstep(0.0, 0.02, brett) * smoothstep(1.0, 0.98, brett));
		rau = 0.55 * trau;
		spec = 0.35;
	} else if (art == 5) {
		float zh = 0.075;
		float zb = 0.24;
		float reihe = floor(wp.y / zh);
		float x = entlang / zb + 0.5 * mod(reihe, 2.0);
		float id = uz_hash2(vec2(floor(x), reihe));
		float fx = fract(x);
		float fy = fract(wp.y / zh);
		float fuge = smoothstep(0.0, 0.05, fx) * smoothstep(1.0, 0.95, fx) * smoothstep(0.0, 0.12, fy) * smoothstep(1.0, 0.88, fy);
		vec3 stein = farbe * (0.78 + 0.32 * id) * (0.9 + 0.2 * hellig);
		c = mix(vec3(0.78, 0.75, 0.7) * (0.9 + 0.1 * putz), stein, fuge);
		rau = mix(0.98, 0.9 * trau, fuge);
		nstaerke *= 1.5;
	} else if (art == 6) {
		vec2 tafel = vec2(fract(entlang / 1.2), fract(wp.y / 0.9));
		float stoss = smoothstep(0.0, 0.004, tafel.x) * smoothstep(1.0, 0.996, tafel.x);
		float loch = uz_kreis((tafel - vec2(0.15, 0.2)) * vec2(1.2, 0.9), 0.012) + uz_kreis((tafel - vec2(0.85, 0.2)) * vec2(1.2, 0.9), 0.012);
		c = grund * mix(0.82, 1.0, stoss) * (1.0 - 0.35 * loch);
		rau = 0.78 * trau;
	} else if (art == 7) {
		float fh = 0.075;
		float fb = 0.15;
		float reihe = floor(wp.y / fh);
		float x = entlang / fb + 0.5 * mod(reihe, 2.0);
		vec2 f = vec2(fract(x), fract(wp.y / fh));
		float fuge = smoothstep(0.0, 0.025, f.x) * smoothstep(1.0, 0.975, f.x) * smoothstep(0.0, 0.05, f.y) * smoothstep(1.0, 0.95, f.y);
		c = mix(vec3(0.85, 0.83, 0.8), farbe * (0.96 + 0.06 * uz_hash2(vec2(floor(x), reihe))), fuge);
		rau = mix(0.9, 0.2, fuge);
		spec = 0.6;
		nstaerke *= 0.4;
	}
	if ((paneel > 0.5 || art == 3) && wp.y < paneel_hoehe) {
		float brett = fract(entlang / 0.14);
		float fuge = smoothstep(0.0, 0.03, brett) * smoothstep(1.0, 0.97, brett);
		float leiste = smoothstep(paneel_hoehe - 0.05, paneel_hoehe - 0.035, wp.y);
		c = paneel_farbe * (0.95 + 0.05 * uz_noise2(vec2(entlang * 7.0, wp.y * 0.8))) * mix(0.68, 1.0, fuge);
		c = mix(c, paneel_farbe * 1.06, leiste);
		rau = 0.45;
		nstaerke *= 0.5;
	}
	// Normalkarte auf Wandkoordinaten: T entlang der Wand, B nach oben (Decke: T = x, B = z).
	vec3 nm = texture(t_normal, tuv).xyz * 2.0 - 1.0;
	nm.xy *= nstaerke;
	vec3 T = decke ? vec3(1.0, 0.0, 0.0) : (abs(wn.z) > 0.5 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0));
	vec3 B = decke ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	vec3 n_welt = normalize(T * nm.x + B * nm.y + wn * max(nm.z, 0.2));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_welt, 0.0)).xyz);
	float ao = 1.0;
	ao -= 0.30 * exp(-max(wp.y, 0.0) / 0.22) * eigen_ao;
	ao -= 0.16 * exp(-max(hoehe - wp.y, 0.0) / 0.18) * eigen_ao;
	ao -= 0.28 * exp(-max(ecke, 0.0) / 0.3) * eigen_ao;
	if (uz_backen(CAMERA_VISIBLE_LAYERS)) {
		// Backen: nur das ankommende Licht (weiß, matt, glatt, ohne Eigenlicht).
		ALBEDO = vec3(1.0);
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	} else {
		float lm = uz_lm_anteil(wn);
		vec3 grund_ao = c * clamp(ao, 0.35, 1.0);
		ALBEDO = grund_ao * (1.0 - lm);
		EMISSION = c * (eigen * clamp(ao, 0.5, 1.0) + (uz_lampen(wp, wn) + uz_fleck(wp, wn)) * clamp(ao + 0.15, 0.5, 1.0));
		if (lm > 0.0) {
			EMISSION += grund_ao * uz_lm(wp) * uz_relief(wp, wn, n_welt) * lm;
		}
		ROUGHNESS = clamp(rau, 0.05, 1.0);
		SPECULAR = spec;
	}
}

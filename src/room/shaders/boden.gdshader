// Boden: gescannte Dielen (ambientCG WoodFloor043, CC0), Marmor, Fliesen, Beton und Teppich aus
// Karten (Albedo, Normal, Rauheit; stoffe.gd TEXTUREN), auf Raumkoordinaten gelegt und um den
// Mittelwert der Karte in die gewählte Farbe getönt. Fischgrät dreht die Dielenkarte je Stab,
// Schachbrett und Terrakotta zeichnen ihre Fugen darüber. Kontaktschatten der Möbel aus der
// Bodenkarte (ao_karte); Lampen und Sonnenfleck aus lichter.gdshaderinc nur im Kompatibilitäts-
// Renderer (eigen_ao, lampen_n). In Forward+ Licht aus der gebackenen Lichtkarte (wie wand.gdshader),
// Glanz aus Reflexionssonde und Himmel.
shader_type spatial;
render_mode diffuse_burley, specular_disabled;

#include "res://src/room/shaders/rauschen.gdshaderinc"
#include "res://src/room/shaders/lichter.gdshaderinc"

uniform vec3 hell : source_color = vec3(0.73, 0.55, 0.37);
uniform vec3 dunkel : source_color = vec3(0.56, 0.39, 0.25);
uniform int art = 0;          // 0 Dielen, 1 Teppichboden, 2 Fliesen, 3 Fischgrät, 4 Schachbrett, 5 Terrazzo, 6 Beton, 7 Marmor
uniform float diele = 0.19;   // Breite der Dielen (Landhausdielen breiter)
uniform vec3 zweit : source_color = vec3(0.82, 0.78, 0.72);   // Fugen, zweite Fliese, Splitter, Adern
uniform vec2 raum = vec2(6.0, 5.0);
uniform float glanz = 0.42;
uniform float eigen_ao = 1.0;
uniform sampler2D ao_karte : hint_default_white, filter_linear;   // Kontaktschatten der Möbel (von oben)
uniform sampler2D t_farbe : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_rau : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 t_mass = vec2(2.0, 1.0);
uniform vec3 t_mittel : source_color = vec3(0.47, 0.33, 0.22);
uniform float t_rau_mittel = 0.5;
uniform float t_staerke = 1.0;
uniform float t_farbe_an = 1.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	vec2 tuv = p / t_mass;
	// Ableitungen der Kartenkoordinaten für die Mip-Stufe: Fischgrät springt je Stab in der Karte –
	// aus den gesprungenen Koordinaten wählte die Grafikkarte an jeder Stabkante die kleinste Stufe
	// (helle Striche entlang der Fugen); hier kommen sie aus den stetigen Koordinaten.
	vec2 tdx = dFdx(tuv);
	vec2 tdy = dFdy(tuv);
	float fuge = 1.0;
	vec3 c;
	float rau;
	float spec = 0.5;
	float nstaerke = t_staerke;
	if (art == 0) {
		// Dielen: die Karte trägt Bretter und Stöße; Landhausdielen gröber gekachelt.
		tuv = p / (t_mass * (diele / 0.19));
		tdx = dFdx(tuv);
		tdy = dFdy(tuv);
	} else if (art == 3) {
		// Fischgrät: Stäbe 9 × 45 cm, abwechselnd 45° nach links und rechts; die Holzkarte läuft je
		// Stab längs, die Fugen kommen aus der Stabgeometrie.
		vec2 q = vec2(p.x + p.y, p.y - p.x) * 0.70710678;
		float s = 0.09;
		float l = 0.45;
		float spalte = floor(q.x / l);
		vec2 r = mod(spalte, 2.0) < 1.0 ? q : vec2(q.y, q.x);
		float reihe = floor(r.y / s);
		float x = r.x / l;
		float id = uz_hash2(vec2(floor(x), reihe));
		vec2 f = vec2(fract(x) * l, fract(r.y / s) * s);
		fuge = smoothstep(0.0, 0.003, f.x) * smoothstep(l, l - 0.003, f.x) * smoothstep(0.0, 0.003, f.y) * smoothstep(s, s - 0.003, f.y);
		tuv = vec2(r.x + id * 3.7, r.y * 0.25 + id * 1.3) / t_mass;
		vec2 qx = dFdx(q);
		vec2 qy = dFdy(q);
		if (mod(spalte, 2.0) >= 1.0) {
			qx = qx.yx;
			qy = qy.yx;
		}
		tdx = vec2(qx.x, qx.y * 0.25) / t_mass;
		tdy = vec2(qy.x, qy.y * 0.25) / t_mass;
	} else if (art == 4) {
		float g = 0.3;
		vec2 f = fract(p / g) * g;
		fuge = smoothstep(0.0, 0.003, f.x) * smoothstep(g, g - 0.003, f.x) * smoothstep(0.0, 0.003, f.y) * smoothstep(g, g - 0.003, f.y);
	} else if (art == 2) {
		float g = 0.31;
		vec2 f = fract(p / g) * g;
		fuge = smoothstep(0.0, 0.006, f.x) * smoothstep(g, g - 0.006, f.x) * smoothstep(0.0, 0.006, f.y) * smoothstep(g, g - 0.006, f.y);
	} else if (art == 7) {
		float g = 0.6;
		vec2 f = fract(p / g) * g;
		fuge = smoothstep(0.0, 0.002, f.x) * smoothstep(g, g - 0.002, f.x) * smoothstep(0.0, 0.002, f.y) * smoothstep(g, g - 0.002, f.y);
	} else if (art == 6) {
		vec2 f = fract(p / 1.5);
		fuge = smoothstep(0.0, 0.002, f.x) * smoothstep(1.0, 0.998, f.x) * smoothstep(0.0, 0.002, f.y) * smoothstep(1.0, 0.998, f.y);
	}
	vec3 tex = textureGrad(t_farbe, tuv, tdx, tdy).rgb;
	float trau = textureGrad(t_rau, tuv, tdx, tdy).r / max(t_rau_mittel, 0.05);
	vec3 getoent = hell * tex / max(t_mittel, vec3(0.02));
	float hellig = dot(tex / max(t_mittel, vec3(0.02)), vec3(0.333));
	vec3 grund = mix(hell * hellig, getoent, t_farbe_an);
	if (art == 0 || art == 3) {
		c = grund * mix(0.45, 1.0, fuge);
		rau = mix(0.62, 0.34, glanz) * trau;
	} else if (art == 1) {
		float f2 = uz_noise2(p * 2.3);
		c = mix(dunkel, hell, 0.6 + (f2 - 0.5) * 0.3) * hellig;
		rau = 0.97 * trau;
		spec = 0.12;
	} else if (art == 4) {
		vec2 id2 = floor(p / 0.3);
		vec3 k = mod(id2.x + id2.y, 2.0) < 1.0 ? hell : zweit;
		c = mix(vec3(0.55, 0.53, 0.5), k * (0.9 + 0.2 * hellig), fuge);
		rau = mix(0.9, 0.22 * trau, fuge);
		spec = 0.6;
	} else if (art == 5) {
		float n = uz_noise2(p * 70.0);
		float splitter = step(0.72, uz_noise2(p * 26.0 + 3.0));
		float fein = step(0.8, uz_noise2(p * 90.0 + 7.0));
		c = hell * (0.94 + 0.08 * n);
		c = mix(c, zweit, splitter * 0.85);
		c = mix(c, dunkel, fein * 0.5);
		rau = 0.3 * trau;
		spec = 0.55;
		nstaerke *= 0.3;
	} else if (art == 6) {
		c = grund * mix(0.75, 1.0, fuge);
		rau = 0.68 * trau;
		spec = 0.4;
	} else if (art == 7) {
		// Marmor: die Karte (dunkler Stein mit hellen Adern) liefert die Adern; Grundton und
		// Aderfarbe wählt der Nutzer (hell, zweit).
		float ader = smoothstep(0.14, 0.7, dot(tex, vec3(0.333)));
		c = mix(hell, zweit, ader * 0.8) * mix(0.8, 1.0, fuge);
		rau = mix(0.8, 0.14 * clamp(trau, 0.6, 2.0), fuge);
		spec = 0.7;
		nstaerke *= 0.6;
	} else {
		vec2 id2 = floor(p / 0.31);
		float id = uz_hash2(id2);
		c = mix(dunkel, hell, clamp(0.3 + id * 0.45 + (hellig - 1.0) * 0.6, 0.0, 1.0));
		c = mix(zweit, c, fuge);
		rau = mix(0.95, 0.5 * trau, fuge);
	}
	// Normalkarte in der Bodenebene (T = x, B = z); Fischgrät: Karte je Stab gedreht.
	vec3 nm = textureGrad(t_normal, tuv, tdx, tdy).xyz * 2.0 - 1.0;
	nm.xy *= nstaerke;
	vec3 T = vec3(1.0, 0.0, 0.0);
	vec3 B = vec3(0.0, 0.0, 1.0);
	if (art == 3) {
		T = vec3(0.70710678, 0.0, 0.70710678);
		B = vec3(-0.70710678, 0.0, 0.70710678);
	}
	vec3 n_welt = normalize(T * nm.x + B * nm.y + vec3(0.0, 1.0, 0.0) * max(nm.z, 0.2));
	// Fugen senken die Fläche ein wenig (Kante dunkler, Normale kippt zur Fuge).
	NORMAL = normalize((VIEW_MATRIX * vec4(n_welt, 0.0)).xyz);
	float wand = min(min(p.x, raum.x - p.x), min(p.y, raum.y - p.y));
	float ao = (1.0 - 0.34 * exp(-max(wand, 0.0) / 0.32) * eigen_ao) * texture(ao_karte, p / raum).r;
	vec3 hoch = vec3(0.0, 1.0, 0.0);
	if (uz_backen(CAMERA_VISIBLE_LAYERS)) {
		ALBEDO = vec3(1.0);
		NORMAL = normalize((VIEW_MATRIX * vec4(hoch, 0.0)).xyz);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	} else {
		float lm = uz_lm_anteil(hoch);
		ALBEDO = c * ao * (1.0 - lm);
		EMISSION = c * ao * (uz_lampen(wp + hoch * 0.01, hoch) + uz_fleck(wp, hoch));
		if (lm > 0.0) {
			EMISSION += c * ao * uz_lm(wp) * uz_relief(wp, hoch, n_welt) * lm;
		}
		ROUGHNESS = clamp(rau, 0.05, 1.0);
		SPECULAR = spec;
	}
}

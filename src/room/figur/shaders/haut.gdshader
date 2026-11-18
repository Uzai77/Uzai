// Haut der Figur und Fell des Haustiers, dazu das Gesicht: Augen, Brauen, Mund, Wangen und
// Sommersprossen werden hier gezeichnet (Abstandsfelder auf der Kopfkugel, keine Bilder) – scharf
// aus jeder Nähe, Blinzeln und Mienen nur über Parameter. Das Gesicht liegt um +z, gemessen in
// Winkeln auf der Kugel (u waagrecht, v senkrecht, Bogenmaß).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/room/shaders/rauschen.gdshaderinc"
#include "res://src/room/figur/shaders/gesicht.gdshaderinc"

uniform vec3 grund : source_color = vec3(0.84, 0.64, 0.48);
uniform vec3 zweit : source_color = vec3(0.95, 0.9, 0.82);
uniform int fell = 0;             // 0 Haut, 1 Fell
uniform int muster = 0;           // Fell: 0 einfarbig, 1 heller Bauch, 2 getigert, 3 gefleckt, 5 Sterne
uniform vec3 bauch_achse = vec3(0.0, -1.0, 0.35);
uniform float bauch_ab = 0.3;
uniform vec3 streifen_achse = vec3(0.0, 0.0, 1.0);

uniform bool gesicht = false;

varying vec3 lp;
varying vec3 ln;

void vertex() {
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lp = VERTEX * s;
	ln = VERTEX;
}

void fragment() {
	vec3 n = normalize(ln);
	vec3 c = grund;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	if (fell == 1) {
		vec3 nl = normalize(lp + vec3(1e-5));
		if (muster == 1 || muster == 2 || muster == 3 || muster == 5) {
			float t = dot(n, normalize(bauch_achse)) + (uz_noise3(lp * 30.0) - 0.5) * 0.12;
			c = mix(c, zweit, smoothstep(bauch_ab - 0.07, bauch_ab + 0.07, t) * (muster == 1 ? 1.0 : 0.85));
		}
		if (muster == 2) {
			float s = dot(lp, normalize(streifen_achse)) * 44.0 + (uz_noise3(lp * 14.0) - 0.5) * 2.4;
			float st = smoothstep(0.42, 0.78, sin(s) * 0.5 + 0.5) * smoothstep(-0.35, 0.25, n.y);
			c = mix(c, grund * 0.5, st * 0.85);
		}
		if (muster == 3) {
			float f = smoothstep(0.66, 0.7, uz_noise3(lp * 16.0 + vec3(3.1)));
			c = mix(c, grund * 0.42, f);
		}
		// Feines Fell: Körnung, etwas heller an den Kanten (Licht im Flaum).
		float k = uz_noise3(lp * 140.0);
		c *= 0.94 + 0.1 * k;
		c += c * fres * 0.38;
	} else {
		c += vec3(0.9, 0.35, 0.25) * fres * 0.12;
	}
	vec3 em = vec3(0.0);
	if (fell == 1 && muster == 5) {
		// Sternenfell: winzige goldene Funken.
		vec3 g = lp * 34.0;
		vec3 zelle = floor(g);
		float h = uz_hash3(zelle);
		if (h > 0.9) {
			vec3 m = zelle + 0.5 + (vec3(uz_hash3(zelle + 1.3), uz_hash3(zelle + 2.7), uz_hash3(zelle + 5.1)) - 0.5) * 0.5;
			float d = length(g - m);
			float a = 1.0 - smoothstep(0.08, 0.2, d);
			c = mix(c, vec3(1.0, 0.86, 0.5), a);
			em += vec3(1.0, 0.8, 0.45) * a * 0.6;
		}
	}
	float rough = fell == 1 ? 0.86 : 0.58;
	float spec = fell == 1 ? 0.2 : 0.32;
	if (gesicht && n.z > 0.0) {
		float u = atan(n.x, n.z);
		float v = asin(clamp(n.y, -1.0, 1.0));
		float aa = max(fwidth(u), fwidth(v)) * 0.9 + 0.0008;
		c = gesicht_malen(c, grund, vec2(u, v), aa, rough, spec);
	}
	ALBEDO = c * COLOR.rgb;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = em;
}

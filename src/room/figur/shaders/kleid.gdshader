// Stoff (Halsband und Halstuch des Haustiers): feine Webung und Samtschimmer wie die Polster im
// Zimmer, dazu eigene Muster (Streifen, Karo, Punkte, Brustband, Sterne, Pixel) – alles gerechnet,
// keine Bilder. Muster liegen um das Teil herum (Bogenlänge um die Achse, Höhe), so laufen sie
// rundum gleich breit.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://src/room/shaders/rauschen.gdshaderinc"

uniform vec3 farbe : source_color = vec3(0.79, 0.59, 0.25);
uniform vec3 muster_farbe : source_color = vec3(0.91, 0.87, 0.81);
uniform int muster = 0;           // 0 einfarbig, 1 Streifen, 2 Karo, 3 Punkte, 4 Brustband, 5 Sterne, 6 Pixel
uniform float schimmer = 0.3;
uniform float rauheit = 0.9;
uniform vec2 band_y = vec2(9.0, 9.0);   // Brustband: von … bis (Höhe im Teil)

varying vec3 lp;

void vertex() {
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lp = VERTEX * s;
}

float stern(vec2 p, float r) {
	// Fünfzackiger Stern (Abstandsfeld, eigene Fassung).
	float w = atan(p.y, p.x);
	float l = length(p);
	float k = cos(floor(0.5 + w / 1.2566) * 1.2566 - w);
	float f = mix(0.48, 1.0, pow(abs(k), 6.0));
	return l - r * f;
}

void fragment() {
	vec2 c = vec2(atan(lp.x, lp.z) * max(length(lp.xz), 0.02), lp.y);
	float aa = fwidth(c.y) * 1.5 + 0.0005;
	vec3 col = farbe;
	float m = 0.0;
	if (muster == 1) {
		m = smoothstep(-aa * 40.0, aa * 40.0, sin(c.y * 6.2831 * 11.0) - 0.15);
	} else if (muster == 2) {
		float a = smoothstep(-0.3, 0.3, sin(c.x * 6.2831 * 9.0));
		float b = smoothstep(-0.3, 0.3, sin(c.y * 6.2831 * 9.0));
		m = (a + b) * 0.36;
		float fein = max(1.0 - smoothstep(0.0, 0.08, abs(fract(c.x * 18.0) - 0.5)), 1.0 - smoothstep(0.0, 0.08, abs(fract(c.y * 18.0) - 0.5)));
		col = mix(col, col * 0.7, fein * 0.35);
	} else if (muster == 3) {
		vec2 g = c * 15.0;
		g.x += step(1.0, mod(floor(g.y), 2.0)) * 0.5;
		m = 1.0 - smoothstep(0.2, 0.2 + aa * 30.0, length(fract(g) - 0.5));
	} else if (muster == 4) {
		m = step(band_y.x, lp.y) * step(lp.y, band_y.y);
	} else if (muster == 5) {
		vec2 g = c * 11.0;
		g.x += step(1.0, mod(floor(g.y), 2.0)) * 0.5;
		vec2 z = floor(g);
		vec2 q = fract(g) - 0.5;
		float w = uz_hash2(z) * 1.2;
		q = mat2(vec2(cos(w), sin(w)), vec2(-sin(w), cos(w))) * q;
		m = 1.0 - smoothstep(0.0, aa * 30.0, stern(q, 0.3));
	} else if (muster == 6) {
		vec2 z = floor(c * 34.0);
		float h = uz_hash2(z);
		m = step(0.82, h);
		col = mix(col, col * 0.82, step(0.62, h) * (1.0 - m));
	}
	col = mix(col, muster_farbe, m);
	// Webung, unruhiger Stoff, weicher Schimmer an den Kanten.
	vec2 uv = c * 520.0;
	float w = 0.5 + 0.5 * sin(uv.x) * sin(uv.y);
	float n = uz_noise2(c * 30.0);
	col *= 0.92 + 0.06 * w + 0.07 * (n - 0.5);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	col += col * fres * schimmer;
	if (!FRONT_FACING) {
		col *= 0.45;
	}
	ALBEDO = col * COLOR.rgb;
	ROUGHNESS = rauheit;
	SPECULAR = 0.2;
}

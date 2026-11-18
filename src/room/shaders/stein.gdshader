// Stein und Geflecht für Möbel (Anpassen, gestalt.gd): 0 Marmor mit weichen Adern, 1 Beton mit
// feinen Poren, 2 Terrazzo mit Splittern, 3 Rattan-Geflecht. Muster im Raum des Möbels (wandert mit).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/room/shaders/rauschen.gdshaderinc"

uniform vec3 farbe : source_color = vec3(0.92, 0.9, 0.87);
uniform vec3 zweit : source_color = vec3(0.45, 0.43, 0.42);
uniform int art = 0;

varying vec3 op;

void vertex() {
	op = VERTEX + NODE_POSITION_WORLD * 0.613;
}

void fragment() {
	vec3 c = farbe;
	float rau = 0.3;
	float spec = 0.6;
	if (art == 0) {
		float n = uz_noise3(op * 3.0) * 0.6 + uz_noise3(op * 9.0) * 0.4;
		float ader = 1.0 - smoothstep(0.0, 0.05, abs(sin((op.x * 4.0 + op.y * 2.0 + op.z * 3.0 + n * 4.0) * 2.2)));
		c = mix(farbe * (0.95 + 0.07 * n), zweit, ader * 0.6);
		rau = 0.12;
		spec = 0.75;
	} else if (art == 1) {
		float fl = uz_noise3(op * 6.0) * 0.6 + uz_noise3(op * 70.0) * 0.4;
		float pore = step(0.86, uz_noise3(op * 160.0));
		c = farbe * (0.85 + 0.22 * fl) * (1.0 - 0.3 * pore);
		rau = 0.78;
		spec = 0.3;
	} else if (art == 2) {
		float s = step(0.7, uz_noise3(op * 38.0));
		float s2 = step(0.78, uz_noise3(op * 90.0 + 5.0));
		c = farbe * (0.95 + 0.06 * uz_noise3(op * 120.0));
		c = mix(c, zweit, s * 0.9);
		c = mix(c, farbe * 0.45, s2 * 0.6);
		rau = 0.25;
		spec = 0.65;
	} else {
		vec2 p = UV * 22.0;
		float a = sin(p.x * 6.2831) * 0.5 + 0.5;
		float b = sin(p.y * 6.2831) * 0.5 + 0.5;
		float faden = mod(floor(p.x) + floor(p.y), 2.0) < 1.0 ? a : b;
		float loch = smoothstep(0.82, 0.95, (1.0 - a) * (1.0 - b) * 4.0);
		c = farbe * (0.72 + 0.4 * faden) * (1.0 - 0.6 * loch);
		rau = 0.7;
		spec = 0.3;
	}
	ALBEDO = c * COLOR.rgb;
	ROUGHNESS = rau;
	SPECULAR = spec;
}

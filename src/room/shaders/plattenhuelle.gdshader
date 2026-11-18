// Plattenhülle mit eigener, ruhiger Grafik (kein fremdes Cover): je Platte eines von vier Mustern
// in ihrer Farbe – Sonne über dem Horizont, Ringe, Streifen, Punkte –, dazu leichte Pappe.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/room/shaders/rauschen.gdshaderinc"

uniform vec3 farbe : source_color = vec3(0.5, 0.6, 0.5);
uniform vec3 hell : source_color = vec3(0.95, 0.91, 0.84);
uniform vec3 dunkel : source_color = vec3(0.13, 0.12, 0.14);
uniform int muster = 0;

varying vec3 on;

void vertex() {
	on = NORMAL;
}

void fragment() {
	vec2 uv = UV2;
	vec3 c = farbe;
	if (on.z > 0.7) {
		vec2 p = uv - 0.5;
		if (muster == 0) {
			float sonne = 1.0 - smoothstep(0.205, 0.215, length(p - vec2(0.0, 0.04)));
			c = mix(c, hell, sonne * step(p.y, 0.1));
			float linie = step(0.1, p.y);
			c = mix(c, mix(farbe, dunkel, 0.55), linie);
			c = mix(c, hell * 0.92, step(0.1, p.y) * step(fract(p.y * 18.0), 0.18) * (1.0 - smoothstep(0.1, 0.32, abs(p.x))));
		} else if (muster == 1) {
			float r = length(p);
			float ring = step(0.5, fract(r * 9.0)) * step(r, 0.42);
			c = mix(c, mix(farbe, hell, 0.55), ring);
			c = mix(c, dunkel, 1.0 - smoothstep(0.05, 0.055, r));
		} else if (muster == 2) {
			float s = step(0.5, fract((uv.x + uv.y) * 6.0));
			c = mix(c, mix(farbe, dunkel, 0.35), s);
			c = mix(c, hell, (1.0 - smoothstep(0.17, 0.175, abs(p.y))) * 0.9);
		} else {
			vec2 g = fract(uv * 7.0) - 0.5;
			float punkt = 1.0 - smoothstep(0.18, 0.2, length(g));
			c = mix(c, mix(farbe, hell, 0.6), punkt);
		}
	} else {
		c = mix(farbe, dunkel, 0.25);
	}
	float pappe = uz_noise2(uv * 220.0) * 0.06 + uz_noise2(uv * 18.0) * 0.05;
	ALBEDO = c * (0.95 + pappe) * COLOR.rgb;
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
}

// Spielhüllen und Module im Regal (MultiMesh): Farbe je Hülle (COLOR), Abnutzung in
// INSTANCE_CUSTOM.r (viel gespielt = abgegriffen: helle Scheuerstellen an Kanten und Ecken,
// matter, leicht ausgeblichen), INSTANCE_CUSTOM.g: 0 Hülle, 1 Modul. Der Rücken (Vorderseite +z)
// trägt oben ein helles Band und unten den goldenen Punkt.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/room/shaders/rauschen.gdshaderinc"

uniform vec3 punkt : source_color = vec3(0.906, 0.761, 0.49);

varying vec3 on;
varying vec4 eigen;
varying vec3 op;

void vertex() {
	on = NORMAL;
	op = VERTEX;
	eigen = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 c = COLOR.rgb;
	float abn = eigen.r;
	float modul = eigen.g;
	vec2 uv = UV2;
	float rand = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	if (on.z > 0.7) {
		// Rücken: helles Band oben, Punkt unten.
		float band = step(0.045, uv.y) * step(uv.y, 0.13);
		c = mix(c, mix(c, vec3(1.0), 0.75), band * (1.0 - modul));
		vec2 pd = vec2((uv.x - 0.5) * 0.35, uv.y - 0.94);
		float dot_ = 1.0 - smoothstep(0.011, 0.016, length(pd));
		c = mix(c, punkt, dot_ * (1.0 - modul));
	} else if (modul < 0.5) {
		// Seiten und Kanten der Hülle: dunkles Plastik.
		c = mix(c * 0.35, vec3(0.05), 0.55);
	}
	float n = uz_noise3(op * 160.0 + eigen.b * 37.0);
	float n2 = uz_noise3(op * 40.0 + eigen.b * 11.0);
	float scheuer = smoothstep(0.08, 0.0, rand) * smoothstep(0.35, 0.75, n) + smoothstep(0.82, 0.95, n2) * 0.5;
	scheuer *= abn;
	float grau = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(grau) * 1.05, abn * 0.22);
	c = mix(c, vec3(0.78, 0.76, 0.72), clamp(scheuer, 0.0, 1.0) * 0.55);
	ALBEDO = c * COLOR.a;
	ROUGHNESS = mix(0.32, 0.62, abn) + scheuer * 0.2;
	SPECULAR = 0.42;
}

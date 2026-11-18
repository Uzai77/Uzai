// Lavalampe: Glas mit leuchtender Flüssigkeit, in der weiche Wachsblasen langsam steigen und
// sinken (eigenes Abstandsfeld aus ein paar wandernden Kugeln, in Höhe und Winkel des Glases).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 wachs : source_color = vec3(1.0, 0.54, 0.24);
uniform vec3 fluessig : source_color = vec3(0.76, 0.21, 0.12);
uniform float an = 1.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float w = atan(lp.x, lp.z);
	vec2 p = vec2(w * 0.05, lp.y);
	float feld = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float y = 0.12 + 0.1 * sin(TIME * (0.11 + fi * 0.023) + fi * 1.9);
		vec2 m = vec2(0.03 * sin(TIME * 0.07 + fi * 2.3), y);
		float r = 0.022 + 0.01 * sin(fi * 3.1);
		feld += r * r / max(dot(p - m, p - m), 1e-5);
	}
	feld += smoothstep(0.03, 0.0, lp.y) * 1.5;
	float blase = smoothstep(0.9, 1.2, feld);
	vec3 c = mix(fluessig * 0.55, wachs, blase);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = c * 0.4;
	EMISSION = c * mix(0.15, 1.6, an) * (0.8 + 0.4 * blase);
	ROUGHNESS = 0.08;
	SPECULAR = 0.7 + fres * 0.3;
}

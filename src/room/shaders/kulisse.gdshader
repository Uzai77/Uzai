// Hintergrund von oben (Übersicht, Bau-Modus): dunkles Graphit wie der Raum der Oberfläche, unter
// dem Zimmer ein weicher, warmer Schein. Innen ist die Kulisse nie zu sehen (Wände, Himmel davor).
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 oben : source_color = vec3(0.05, 0.052, 0.06);
uniform vec3 unten : source_color = vec3(0.03, 0.03, 0.034);
uniform vec3 schein : source_color = vec3(0.32, 0.22, 0.13);
uniform vec3 mitte = vec3(3.0, 0.0, 2.5);

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 d = normalize(wp - mitte);
	vec3 c = mix(unten, oben, smoothstep(-0.4, 0.6, d.y));
	float s = exp(-pow(max(d.y + 0.15, 0.0) * 2.4, 2.0)) * smoothstep(-0.9, -0.1, d.y);
	c += schein * s * 0.35;
	float rn = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = c + (rn - 0.5) / 255.0;
}

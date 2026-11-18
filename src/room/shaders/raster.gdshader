// Bau-Modus: feines Raster auf dem Boden, um das gewählte Feld kräftiger, nach außen weich aus.
// Das gewählte Feld (bereich in Metern: x, z, Breite, Tiefe) leuchtet im Akzent; unter einem getragenen
// Möbel klar grün (passt) bzw. rot (passt nicht), kräftiger gefüllt – auch auf hellem Holz und Teppich.
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float zelle = 0.5;
uniform vec4 bereich = vec4(0.0, 0.0, 0.5, 0.5);
uniform vec3 farbe : source_color = vec3(0.906, 0.761, 0.49);
uniform vec3 rot : source_color = vec3(0.92, 0.16, 0.18);
uniform vec3 gruen : source_color = vec3(0.10, 0.80, 0.30);
uniform float frei = 1.0;
uniform float getragen = 0.0;
uniform float sicht = 1.0;
uniform vec2 raum = vec2(6.0, 5.0);

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	vec2 g = abs(fract(p / zelle - 0.5) - 0.5) * zelle;
	vec2 fw = fwidth(p) * 1.1;
	float linie = 1.0 - min(smoothstep(fw.x * 0.5, fw.x * 1.5, g.x), smoothstep(fw.y * 0.5, fw.y * 1.5, g.y));
	vec2 mitte = bereich.xy + bereich.zw * 0.5;
	float nah = 1.0 - smoothstep(0.6, 2.8, length(p - mitte) - max(bereich.z, bereich.w) * 0.4);
	vec2 d = abs(p - mitte) - bereich.zw * 0.5;
	float sd = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
	float innen = 1.0 - smoothstep(-0.006, 0.006, sd);
	float rand = 1.0 - smoothstep(0.012, 0.03, abs(sd + 0.022));
	float schein = exp(-max(sd, 0.0) / 0.06) * (1.0 - innen);
	vec3 c = mix(rot, mix(farbe, gruen, getragen), frei);
	float a = linie * (0.04 + 0.3 * nah) + innen * mix(0.3, 0.5, getragen) + rand * 0.95 + schein * 0.35;
	ALBEDO = mix(vec3(1.0, 0.98, 0.94), c, clamp(innen + rand + schein, 0.0, 1.0)) * (1.0 + rand * 0.6);
	ALPHA = clamp(a, 0.0, 1.0) * sicht;
}

// Pokale und kleines Metall: gespiegelte Umgebung als günstiger Fake (wie eine Matcap): aus der
// Spiegelrichtung im Blickraum ein weiches Studio – helles Licht oben, ein Fensterstreifen seitlich,
// warmer Boden, dunkler Horizont. Kein Spiegelbild der Szene, keine Reflexionssonde; die Stärke
// folgt dem Licht im Raum (umgebung, von zimmer_welt.gd gesetzt).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 farbe : source_color = vec3(0.9, 0.75, 0.4);
uniform float rauheit = 0.22;
uniform float umgebung = 1.0;
uniform vec3 oben_farbe : source_color = vec3(1.0, 0.93, 0.82);
uniform vec3 fenster_farbe : source_color = vec3(0.8, 0.88, 1.0);
uniform vec3 boden_farbe : source_color = vec3(0.42, 0.27, 0.15);

void fragment() {
	vec3 r = reflect(-VIEW, NORMAL);
	float weich = 0.12 + rauheit * 0.9;
	// Unten der warme Boden, in der Mitte der Raum (gedämpft, nie schwarz), oben das Licht.
	vec3 raum = mix(boden_farbe * 0.8, oben_farbe * 0.38, smoothstep(-0.55, 0.15, r.y));
	vec3 env = raum + oben_farbe * smoothstep(0.25, 0.25 + weich * 2.0, r.y) * 1.2;
	env += fenster_farbe * exp(-pow((r.x + 0.55) / (0.12 + weich), 2.0)) * smoothstep(-0.35, 0.2, r.y) * 0.9;
	env += oben_farbe * exp(-pow((r.x - 0.7) / (0.08 + weich), 2.0)) * smoothstep(0.0, 0.5, r.y) * 0.45;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	vec3 spiegel = mix(farbe, vec3(1.0), fres * 0.6);
	ALBEDO = farbe * 0.22;
	METALLIC = 0.0;
	ROUGHNESS = clamp(rauheit + 0.12, 0.05, 1.0);
	SPECULAR = 0.35;
	EMISSION = env * spiegel * umgebung * 0.85;
}

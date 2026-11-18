shader_type canvas_item;
// Anmutung Dreamcast: auf warmem Weiß drehen sich orange Wirbelarme aus der Weite zur Mitte,
// werden langsamer und sammeln sich in einem glühenden Kern. Mehrarmig und bewegt – kein
// nachgezeichnetes Zeichen. Eigener Entwurf.
#include "res://src/ui/components/intro/intro.gdshaderinc"

void fragment() {
	vec2 p = ort(UV);
	vec2 q = p - vec2(0.0, 0.16);
	float r = length(q);
	float a = atan(q.y, q.x);
	vec3 weiss = mix(vec3(0.9, 0.885, 0.87), vec3(0.995, 0.99, 0.975), glanz(length(p * vec2(0.6, 1.0)), 1.1));
	vec3 c = mix(vec3(0.0), weiss, e_expo(t / 0.45));
	float zug = e_io(t / 1.45);
	float rmax = mix(2.6, 0.62, zug);
	float spin = 6.5 * (1.0 - exp(-t * 1.5));
	float verdrill = mix(2.0, 3.4, zug);
	float arme = 0.0;
	// Viele feine Arme in drei Lagen, die verschieden schnell drehen: ein Strudel, kein Zeichen.
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float n = 5.0 + fk * 2.0;
		float ph = a * n + verdrill * n * log(r + 0.03) * (1.0 - fk * 0.18) - spin * (1.0 + fk * 0.35) + fk * 1.3;
		float w = 0.5 + 0.5 * cos(ph);
		float flimmer = 0.75 + 0.25 * sin(log(r + 0.03) * 14.0 + fk * 2.0 - spin * 1.5);
		arme += pow(w, 10.0 + fk * 8.0) * (0.85 - fk * 0.22) * flimmer;
	}
	float huelle = smoothstep(rmax, rmax * 0.55, r) * smoothstep(0.0, 0.1, r);
	vec3 orange = mix(vec3(0.98, 0.42, 0.06), vec3(1.0, 0.66, 0.2), smoothstep(rmax, 0.0, r));
	float stark = sat(arme) * huelle * (1.0 - 0.55 * ruhe());
	c = mix(c, orange, stark * 0.92);
	// Funken auf den Armen.
	vec2 g = vec2(a * 6.0 + spin * 2.0, log(r + 0.05) * 9.0);
	vec2 id = floor(g);
	float fun = step(0.86, h21(id)) * glanz(length(fract(g) - 0.5), 0.12) * huelle * arme;
	c = mix(c, vec3(1.0, 0.8, 0.45), sat(fun) * 0.7);
	// Kern: glüht, wenn sich der Wirbel gesammelt hat.
	float kern = e_out((t - 0.9) / 0.6);
	c = mix(c, vec3(1.0, 0.5, 0.1), glanz(r, 0.05 + 0.03 * kern) * kern * 0.9);
	c += vec3(0.25, 0.08, 0.0) * halo(r, 0.06) * kern * 0.35 * (1.0 - 0.5 * ruhe());
	float welle = (t - 1.25) * 1.6;
	c = mix(c, vec3(1.0, 0.62, 0.25), glanz(r - welle, 0.03) * 0.5 * (1.0 - sat(welle / 1.6)) * step(0.0, welle));
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.18), 1.0);
}

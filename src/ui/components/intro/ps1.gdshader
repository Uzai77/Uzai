shader_type canvas_item;
// Anmutung PlayStation: aus dem Schwarz öffnet sich ein heller Lichtspalt zu reinem Weiß, das
// langsam in ein ruhiges, warmes Grau mit weichem Boden übergeht. Eigener Entwurf.
#include "res://src/ui/components/intro/intro.gdshaderinc"

void fragment() {
	vec2 p = ort(UV);
	float a1 = e_out(t / 0.32);
	float a2 = e_expo((t - 0.2) / 0.55);
	float breite = mix(0.03, aspect * 1.25, a1);
	float hoehe = mix(0.002, 1.3, a2);
	vec3 c = vec3(0.0);
	// Der Spalt: je Farbkanal minimal anders breit (zarter Farbsaum an den Kanten).
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float b = breite * (1.0 + (fk - 1.0) * 0.012);
		float dx = max(abs(p.x) - b, 0.0);
		float dy = max(abs(p.y) - hoehe * (1.0 + (fk - 1.0) * 0.02), 0.0);
		float kern = exp(-dx * dx / 0.02) * exp(-dy * dy / (0.0004 + 0.02 * a2));
		float schein = halo(dy, 0.01 + 0.08 * a1) * exp(-dx * 3.0) * 0.5;
		float v = (kern + schein * (1.0 - a2)) * (0.9 + 0.5 * buckel(0.25, 0.9, t));
		if (k == 0) { c.r = v; } else if (k == 1) { c.g = v; } else { c.b = v * 1.03; }
	}
	// Abkühlen: Weiß wird zu Grau mit Licht von oben und einem weichen Boden.
	float kuehl = e_sin((t - 0.6) / 1.1);
	float y = p.y;
	vec3 grau = mix(vec3(0.66, 0.665, 0.68), vec3(0.93, 0.93, 0.935), smoothstep(-0.9, 0.8, y));
	grau += vec3(0.06) * glanz(length(vec2(p.x * 0.45, y - 0.9)), 0.7);
	float boden = smoothstep(-0.32, -0.42, y);
	grau = mix(grau, grau * 0.86, boden);
	grau += vec3(0.05) * glanz(y + 0.37, 0.012) * (1.0 - smoothstep(0.4, 1.6, abs(p.x)));
	// Feine Lichtringe, die sich beim Abkühlen weit ausbreiten.
	float ringe = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float rr = (t - 0.55 - fi * 0.16) * 1.5;
		ringe += glanz(length(p * vec2(0.6, 1.0)) - rr, 0.06) * (1.0 - sat(rr / 2.2)) * step(0.0, rr);
	}
	vec3 weiss = c;
	c = mix(weiss, grau, kuehl * smoothstep(0.5, 1.0, a2));
	c += vec3(0.04) * ringe * (1.0 - ruhe());
	// Schwebender Staub im Licht.
	vec2 g = p * 9.0 + vec2(t * 0.15, -t * 0.25);
	vec2 id = floor(g);
	float r = h21(id);
	float staub = step(0.85, r) * glanz(length(fract(g) - 0.5 - (h22(id) - 0.5) * 0.6), 0.04);
	c -= vec3(0.05) * staub * kuehl;
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.25), 1.0);
}

shader_type canvas_item;
// Anmutung Nintendo DS und 3DS: zwei Schirme übereinander erwachen nacheinander, ein Lichtstrich
// läuft über das Scharnier hinab, eine Berührung zieht Kreise auf dem unteren Schirm.
// variante 0: Silber und Weiß (DS), 1: oben Tiefe in Ebenen, roter Schimmer (3DS). Eigener Entwurf.
#include "res://src/ui/components/intro/intro.gdshaderinc"

void fragment() {
	vec2 p = ort(UV);
	bool d3 = variante > 0.5;
	vec3 tint = d3 ? vec3(0.85, 0.2, 0.25) : vec3(0.6, 0.65, 0.75);
	vec3 c = mix(vec3(0.03, 0.032, 0.036), vec3(0.12, 0.125, 0.135), glanz(p.y, 1.1));
	c *= e_out(t / 0.4);
	vec2 top_at = vec2(0.0, 0.45);
	vec2 bot_at = vec2(0.0, -0.47);
	vec2 tb = d3 ? vec2(0.66, 0.36) : vec2(0.56, 0.36);
	vec2 bb = vec2(0.5, 0.36);
	float auf = e_out((t - 0.05) / 0.5);
	// Rahmen der beiden Hälften.
	float rah_o = sd_rbox(p - top_at, tb + 0.08, 0.1);
	float rah_u = sd_rbox(p - bot_at, bb + 0.1, 0.1);
	float rah = min(rah_o, rah_u);
	c = mix(c, vec3(0.16, 0.165, 0.18) + 0.05 * glanz(rah + 0.02, 0.02), kante(rah) * auf);
	// Oberer Schirm wacht auf, mit kurzem Flackern; unterer folgt.
	float an_o = e_out((t - 0.3) / 0.35) * (0.85 + 0.15 * step(0.5, fract(t * 30.0)) * (1.0 - step(0.55, t)));
	float an_u = e_out((t - 0.85) / 0.35);
	vec2 qo = p - top_at;
	vec2 qu = p - bot_at;
	float io = kante(sd_rbox(qo, tb, 0.03));
	float iu = kante(sd_rbox(qu, bb, 0.03));
	vec3 hell = mix(vec3(0.97, 0.975, 0.98), tint, 0.06);
	vec3 so = mix(vec3(0.05, 0.055, 0.06), hell, an_o);
	if (d3) {
		// Tiefe: drei Ebenen, die sich gegeneinander verschieben.
		for (int k = 0; k < 3; k++) {
			float fk = float(k);
			vec2 o = qo + vec2(sin(t * 0.9 + fk) * 0.02 * (fk + 1.0), 0.0);
			float wellen = sin(o.x * (4.0 + fk * 2.0) + t * (1.0 + fk * 0.4)) * 0.05 - 0.12 + fk * 0.1;
			float ebene = kante(o.y - wellen);
			so = mix(so, mix(hell, tint, 0.25 + 0.2 * fk), ebene * an_o * 0.5);
		}
	}
	vec3 su = mix(vec3(0.05, 0.055, 0.06), hell, an_u);
	// Berührung: Kreise vom Tippen aus.
	vec2 tip = vec2(0.18, -0.08);
	for (int k = 0; k < 3; k++) {
		float rr = (t - 1.1 - float(k) * 0.14) * 0.5;
		su = mix(su, tint, strich(length(qu - tip) - rr, 0.004) * 0.5 * step(0.0, rr) * (1.0 - sat(rr / 0.45)));
	}
	c = mix(c, so, io);
	c = mix(c, su, iu);
	// Lichtstrich über das Scharnier.
	float ly = mix(top_at.y - tb.y, bot_at.y + bb.y, e_io((t - 0.55) / 0.35));
	float lichtstrich = glanz(p.y - ly, 0.012) * glanz(p.x, 0.25) * buckel(0.55, 0.95, t);
	c += vec3(0.9, 0.95, 1.0) * lichtstrich;
	c *= 1.0 - 0.15 * ruhe() * (1.0 - io);
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.35), 1.0);
}

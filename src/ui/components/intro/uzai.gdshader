shader_type canvas_item;
// Neutrale Uzai-Sequenz für Systeme ohne eigene: das Zeichen von Uzai, „Schale und Kern“
// (uzai_logo.gd), in der Handschrift der Marke. Matter Grund in einem Hauch der Systemfarbe; der
// Kern zündet (hell, dann Akzent), ein Lichtring läuft einmal aus, das Licht fällt auf die
// Innenseite der Schale und steigt in beiden Flanken zugleich hinauf; oben leuchten beide Kanten
// kurz auf, dann Ruhe für den Namen. Maße wie im 256er-Raster des Zeichens.
#include "res://src/ui/components/intro/intro.gdshaderinc"

const vec2 MID = vec2(128.0, 128.0);
const float RM = 42.0;
const float HW = 14.0;
const float TOP = 72.0;
const float RUND = 4.0;
const float DOT_R = 18.0;
const float L_BOGEN = 65.973;
const float L_FLANKE = 56.0;
const float MASS = 0.0043;      // ort-Einheiten je Rasterpunkt (das Zeichen ist knapp ein Viertel hoch)

float sd_schale(vec2 p) {
	float unten = MID.y + 2.0;
	float my = (TOP + unten) * 0.5;
	float links = sd_rbox(p - vec2(MID.x - RM, my), vec2(HW, (unten - TOP) * 0.5), RUND);
	float rechts = sd_rbox(p - vec2(MID.x + RM, my), vec2(HW, (unten - TOP) * 0.5), RUND);
	float bogen = max(abs(length(p - MID) - RM) - HW, MID.y - p.y);
	return min(min(links, rechts), bogen);
}

// Weg ab dem Grund der Schale (beide Flanken gleich) und Lage quer zum Strich (−1 innen … 1 außen).
vec2 weg(vec2 p) {
	if (p.y < MID.y) {
		return vec2(L_BOGEN + (MID.y - p.y), (abs(p.x - MID.x) - RM) / HW);
	}
	vec2 q = p - MID;
	return vec2(abs(clamp(atan(q.y, q.x), 0.0, PI) - PI * 0.5) * RM, (length(q) - RM) / HW);
}

void fragment() {
	vec2 p = ort(UV);
	vec2 q = p - vec2(0.0, 0.1);
	vec2 r = MID + vec2(q.x, -q.y) / MASS;          // im Raster des Zeichens (y nach unten)
	float bp_r = bildpunkt / MASS;
	vec3 grund = mix(vec3(0.04, 0.042, 0.048), sys_col.rgb * 0.14, 0.5);
	vec3 c = mix(grund * 0.7, grund * 1.25, glanz(length(p * vec2(0.6, 1.0)), 1.0));
	c *= e_out(t / 0.4);
	vec3 acc = acc_col.rgb;
	float zuend = e_out((t - 0.15) / 0.12);
	float hell_k = exp(-max(t - 0.2, 0.0) / 0.2) * zuend;
	float rd = length(r - MID);
	// Licht des Kerns im Raum und ein Lichtring, der einmal ausläuft.
	float licht = e_out((t - 0.18) / 0.7);
	c += acc * glanz(length(q), mix(0.05, 0.75, licht)) * 0.12 * zuend;
	float ring_r = mix(0.08, 1.6, e_out((t - 0.18) / 0.9));
	c += mix(acc, vec3(1.0), 0.4) * glanz(length(q) - ring_r, 0.012 + 0.05 * licht) * 0.16 * (1.0 - licht) * zuend;
	// Die Schale: zuerst die Innenseite im Licht des Kerns, dann steigt das Licht in beiden Flanken.
	float ds = sd_schale(r);
	float bed = kante_bp(ds, bp_r);
	if (bed > 0.0) {
		vec2 w = weg(r);
		float innen = sat(-w.y * 0.8 + 0.4);
		vec3 stoff = mix(grund, vec3(0.95), 0.07) + acc * innen * 0.22 * zuend / (1.0 + rd * rd / 6000.0);
		float fl = e_io((t - 0.42) / 0.55);
		float front = fl * (L_BOGEN + L_FLANKE + 8.0) - 4.0;
		float ist = sat((front - w.x) / 3.0 + 0.5);
		float kopf = glanz(w.x - front, 10.0) * step(0.001, fl) * (1.0 - step(0.999, fl));
		vec3 farbe = mix(stoff, vec3(0.95), ist);
		farbe = mix(farbe, mix(acc, vec3(1.0), 0.55), kopf * 0.85);
		float nach = buckel(0.95, 1.4, t);
		farbe = mix(farbe, vec3(1.0), nach * (0.2 + 0.5 * glanz(w.x - (L_BOGEN + L_FLANKE), 14.0)) * ist);
		c = mix(c, farbe, bed * e_out((t - 0.2) / 0.25));
	}
	// Der Kern: zündet hell und setzt sich zum Akzent, mit hellerer Mitte und einem Glanz oben links.
	float kern = kante_bp(rd - DOT_R, bp_r) * zuend;
	float tief = sat(1.0 - rd / DOT_R);
	vec3 kc = mix(acc, vec3(1.0), 0.75 * hell_k + 0.18 * tief * tief);
	kc = mix(kc, vec3(1.0), glanz(length(r - MID - vec2(-6.0, -7.0)), 6.0) * 0.22);
	c = mix(c, kc, kern);
	c += mix(acc, vec3(1.0), 0.4 * hell_k) * glanz(max(rd - DOT_R, 0.0), DOT_R * (0.6 + 1.4 * hell_k)) * (0.08 + 0.5 * hell_k) * step(DOT_R, rd) * (1.0 - bed * 0.7);
	// Feine, matte Körnung (kein Glas).
	c += (rauschen(FRAGCOORD.xy * 0.7) - 0.5) * 0.012;
	COLOR = vec4(fertig(c, UV, FRAGCOORD.xy, 0.4), 1.0);
}

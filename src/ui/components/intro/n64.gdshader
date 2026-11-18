shader_type canvas_item;
// Anmutung Nintendo 64: vier bunte, weich schattierte Körper (Kugel, Würfel, Ring, Spitzkörper)
// fliegen kreiselnd aus der Tiefe heran, reihen sich auf und wippen im Takt. Satte Farben,
// tiefblauer Nebel. Eigener Entwurf.
#include "res://src/ui/components/intro/intro.gdshaderinc"

vec3 lage(int i) {
	float fi = float(i);
	float an = e_out((t - 0.1 - fi * 0.12) / 1.05);
	vec3 ziel = vec3((fi - 1.5) * 0.95, 0.12 + 0.05 * sin(t * 4.0 + fi * 1.6) * smoothstep(1.0, 1.4, t), 0.0);
	vec3 start = vec3((fi - 1.5) * 3.5 + sin(fi * 2.1) * 2.0, (h11(fi) - 0.3) * 4.0, 16.0);
	return mix(start, ziel, an);
}

mat3 kreisel(int i) {
	float fi = float(i);
	float s = 7.0 * (1.0 - e_out((t - 0.1 - fi * 0.12) / 1.25)) + t * 0.8 + fi;
	float c1 = cos(s);
	float s1 = sin(s);
	float c2 = cos(s * 0.7 + fi);
	float s2 = sin(s * 0.7 + fi);
	mat3 ry = mat3(vec3(c1, 0.0, -s1), vec3(0.0, 1.0, 0.0), vec3(s1, 0.0, c1));
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c2, s2), vec3(0.0, -s2, c2));
	return ry * rx;
}

float koerper(vec3 q, int i) {
	if (i == 0) {
		return length(q) - 0.36;
	} else if (i == 1) {
		return sd_box3(q, vec3(0.28), 0.05);
	} else if (i == 2) {
		vec2 tq = vec2(length(q.xz) - 0.26, q.y);
		return length(tq) - 0.11;
	}
	vec3 a = abs(q);
	return (a.x + a.y + a.z - 0.42) * 0.57735;
}

vec2 szene(vec3 p, vec3 c0, vec3 c1, vec3 c2, vec3 c3, mat3 m0, mat3 m1, mat3 m2, mat3 m3) {
	vec2 r = vec2(koerper(m0 * (p - c0), 0), 0.0);
	float d = koerper(m1 * (p - c1), 1);
	if (d < r.x) { r = vec2(d, 1.0); }
	d = koerper(m2 * (p - c2), 2);
	if (d < r.x) { r = vec2(d, 2.0); }
	d = koerper(m3 * (p - c3), 3);
	if (d < r.x) { r = vec2(d, 3.0); }
	return r;
}

void fragment() {
	vec2 p = ort(UV);
	vec3 c0 = lage(0);
	vec3 c1 = lage(1);
	vec3 c2 = lage(2);
	vec3 c3 = lage(3);
	mat3 m0 = kreisel(0);
	mat3 m1 = kreisel(1);
	mat3 m2 = kreisel(2);
	mat3 m3 = kreisel(3);
	vec3 ro = vec3(0.0, 0.25, -4.2);
	vec3 rd = normalize(vec3(p.x, p.y - 0.04, 2.2));
	vec3 nebel = mix(vec3(0.01, 0.02, 0.08), vec3(0.05, 0.1, 0.3), glanz(p.y + 0.1, 0.9));
	vec3 col = nebel;
	// Ferne Bodenlinien in Perspektive.
	if (p.y < -0.3) {
		float zf = 0.75 / (-p.y - 0.25);
		vec2 w = vec2(p.x * zf, zf - t * 1.2);
		vec2 l = abs(fract(w) - 0.5);
		col += vec3(0.1, 0.25, 0.7) * (strich_bp(min(l.x, l.y), 0.008 * zf, bildpunkt * zf) + 0.25 * glanz(min(l.x, l.y), 0.02 * zf)) * exp(-zf * 0.25) * 0.35;
	}
	// Zuerst gegen die Hüllkugeln der vier Körper: Strahlen, die keinen berühren (der größte Teil des
	// Schirms), kosten so nichts – auch in 4K. Dann nur zwischen erstem Eintritt und letztem Austritt.
	float von = 1e9;
	float bis = -1.0;
	for (int i = 0; i < 4; i++) {
		vec3 oc = ro - (i == 0 ? c0 : (i == 1 ? c1 : (i == 2 ? c2 : c3)));
		float b = dot(oc, rd);
		float hh = b * b - (dot(oc, oc) - 0.3);
		if (hh > 0.0) {
			von = min(von, max(-b - sqrt(hh), 0.0));
			bis = max(bis, -b + sqrt(hh));
		}
	}
	float d = von;
	vec2 h = vec2(1.0, -1.0);
	// Engster Vorbeigang (für die geglättete Silhouette): Winkel und Abstand.
	float best = 1e9;
	float db = 0.0;
	float pw = bildpunkt / 2.2;
	if (bis > 0.0) {
		for (int i = 0; i < 80; i++) {
			h = szene(ro + rd * d, c0, c1, c2, c3, m0, m1, m2, m3);
			if (h.x < 0.0015 || d > bis) {
				break;
			}
			float r = h.x / max(d, 0.05);
			if (r < best) {
				best = r;
				db = d;
			}
			d += h.x * 0.9;
		}
	}
	float deck = h.x < 0.0015 ? 1.0 : sat(1.0 - best / pw);
	if (h.x >= 0.0015 && deck > 0.0) {
		d = db;
		h = szene(ro + rd * d, c0, c1, c2, c3, m0, m1, m2, m3);
	}
	if (deck > 0.0) {
		vec3 pos = ro + rd * d;
		vec2 e = vec2(0.002, -0.002);
		vec3 n = normalize(e.xyy * szene(pos + e.xyy, c0, c1, c2, c3, m0, m1, m2, m3).x
				+ e.yyx * szene(pos + e.yyx, c0, c1, c2, c3, m0, m1, m2, m3).x
				+ e.yxy * szene(pos + e.yxy, c0, c1, c2, c3, m0, m1, m2, m3).x
				+ e.xxx * szene(pos + e.xxx, c0, c1, c2, c3, m0, m1, m2, m3).x);
		vec3 farbe = h.y < 0.5 ? vec3(0.88, 0.12, 0.1) : (h.y < 1.5 ? vec3(0.1, 0.62, 0.22) : (h.y < 2.5 ? vec3(0.12, 0.28, 0.85) : vec3(0.98, 0.76, 0.08)));
		vec3 l = normalize(vec3(-0.5, 0.8, -0.55));
		float dif = max(dot(n, l), 0.0);
		float spec = pow(max(dot(reflect(-l, n), -rd), 0.0), 24.0);
		float rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
		vec3 flaeche = farbe * (0.2 + 0.85 * dif) + vec3(1.0) * spec * 0.5 + mix(farbe, vec3(0.5, 0.7, 1.0), 0.5) * rim * 0.35;
		flaeche = mix(flaeche, nebel, 1.0 - exp(-max(d - 3.5, 0.0) * 0.12));
		col = mix(col, flaeche, deck);
	}
	col *= 1.0 - 0.3 * ruhe() * glanz(p.y + 0.42, 0.18);
	col *= e_out(t / 0.4);
	COLOR = vec4(fertig(col, UV, FRAGCOORD.xy, 0.5), 1.0);
}

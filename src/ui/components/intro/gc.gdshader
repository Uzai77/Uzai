shader_type canvas_item;
// Anmutung GameCube: ein violetter Würfel aus acht Teilen rollt in drei Kippern über einen
// spiegelnden Boden, setzt auf, faltet sich kurz auf (Licht aus den Fugen) und schließt sich
// wieder. Eigener Entwurf, kein Nachbau des Original-Starts.
#include "res://src/ui/components/intro/intro.gdshaderinc"

const float H = 0.5;

float wuerfel(vec3 p, vec3 c, float a, float g, float yaw) {
	vec3 q = p - c;
	q.xy = dreh(a) * q.xy;
	q.xz = dreh(yaw) * q.xz;
	vec3 s = abs(q) - vec3(H * 0.5 + g * 0.5);
	return sd_box3(s, vec3(H * 0.5), 0.045);
}

vec3 normale(vec3 p, vec3 c, float a, float g, float yaw) {
	vec2 e = vec2(0.0015, -0.0015);
	return normalize(e.xyy * wuerfel(p + e.xyy, c, a, g, yaw) + e.yyx * wuerfel(p + e.yyx, c, a, g, yaw)
			+ e.yxy * wuerfel(p + e.yxy, c, a, g, yaw) + e.xxx * wuerfel(p + e.xxx, c, a, g, yaw));
}

// Strahl gegen den Würfel: (Abstand des Treffers oder −1, Abdeckung des Rands, Abstand des
// engsten Vorbeigangs). Zuerst gegen eine Hüllkugel – Strahlen, die den Würfel nicht berühren (fast
// der ganze Schirm), kosten so nichts, auch in 4K. pw: Winkel eines Bildpunkts; ein Strahl, der
// knapp vorbeigeht, deckt den Rand anteilig (geglättete Silhouette statt Treppen).
vec3 marsch(vec3 ro, vec3 rd, vec3 c, float a, float g, float yaw, int n, float pw) {
	vec3 oc = ro - c;
	float rad = (H + g * 0.5) * 1.7321 + 0.08;
	float b = dot(oc, rd);
	float hh = b * b - (dot(oc, oc) - rad * rad);
	if (hh < 0.0) {
		return vec3(-1.0, 0.0, 0.0);
	}
	float d = max(-b - sqrt(hh), 0.0);
	float ende = -b + sqrt(hh);
	float best = 1e9;
	float db = d;
	for (int i = 0; i < n; i++) {
		float h = wuerfel(ro + rd * d, c, a, g, yaw);
		if (h < 0.0012) {
			return vec3(d, 1.0, d);
		}
		float r = h / max(d, 0.05);
		if (r < best) {
			best = r;
			db = d;
		}
		d += h;
		if (d > ende) {
			break;
		}
	}
	return vec3(-1.0, sat(1.0 - best / pw), db);
}

vec3 himmel(vec3 rd) {
	return mix(vec3(0.03, 0.018, 0.07), vec3(0.22, 0.15, 0.42), sat(rd.y * 1.6 + 0.3));
}

vec3 flaeche(vec3 pos, vec3 rd, vec3 c, float a, float g, float yaw) {
	vec3 n = normale(pos, c, a, g, yaw);
	vec3 l = normalize(vec3(-0.55, 0.85, -0.6));
	float dif = max(dot(n, l), 0.0);
	float spec = pow(max(dot(reflect(-l, n), -rd), 0.0), 40.0);
	float fres = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);
	float rand = pow(max(dot(n, normalize(vec3(0.8, 0.3, 0.6))), 0.0), 3.0);
	vec3 farbe = vec3(0.38, 0.28, 0.8);
	vec3 col = farbe * (0.24 + 0.95 * dif) + vec3(1.0, 0.94, 1.0) * spec * 0.85;
	col += himmel(reflect(rd, n)) * fres * 0.9 + vec3(0.55, 0.45, 1.0) * rand * 0.18;
	// Fugen: Licht dringt aus dem Inneren, wenn sich der Würfel öffnet.
	vec3 q = pos - c;
	q.xy = dreh(a) * q.xy;
	q.xz = dreh(yaw) * q.xz;
	float fuge = min(abs(q.x), min(abs(q.y), abs(q.z)));
	col += vec3(0.85, 0.75, 1.0) * glanz(fuge, 0.012 + g * 0.6) * (0.08 + g * 12.0);
	// Innen ein warmes Licht, das die Innenflächen in den Fugen erhellt.
	col += vec3(0.95, 0.85, 1.0) * exp(-length(q) * 3.5) * g * 14.0;
	return col;
}

void fragment() {
	vec2 p = ort(UV);
	// Rollen: drei Viertel-Kipper, je mit kurzer Pause (das „Plonk“ beim Aufsetzen).
	float roll = 0.0;
	for (int k = 0; k < 3; k++) {
		roll += e_io((t - 0.2 - float(k) * 0.36) / 0.3);
	}
	float kk = min(floor(roll), 2.0);
	float a = (roll - kk) * PI * 0.5;
	float g = 0.11 * buckel(1.22, 1.9, t);
	float yaw = e_io((t - 1.2) / 1.1) * PI * 0.5;
	vec2 piv = vec2(-3.0 + kk * 2.0 * H + H, 0.0);
	vec3 c = vec3(piv + vec2(-H * cos(a) + H * sin(a), H * sin(a) + H * cos(a)), 0.0);
	c.y += g;
	vec3 ro = vec3(1.9, 2.1, -3.3);
	vec3 ziel = vec3(-0.6 * (1.0 - e_out(t / 1.6)), 0.4, 0.0);
	vec3 fw = normalize(ziel - ro);
	vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
	vec3 up = cross(fw, rt);
	vec3 rd = normalize(fw * 2.2 + rt * p.x + up * p.y);
	vec3 col = himmel(rd);
	col += vec3(0.35, 0.22, 0.8) * halo(length((p - vec2(0.0, 0.2)) * vec2(0.6, 1.0)), 0.3) * 0.22;
	float pw = bildpunkt / 2.2;
	vec3 mw = marsch(ro, rd, c, a, g, yaw, 72, pw);
	float dw = mw.x;
	float df = rd.y < 0.0 ? -ro.y / rd.y : -1.0;
	if (dw > 0.0 && (df < 0.0 || dw < df)) {
		col = flaeche(ro + rd * dw, rd, c, a, g, yaw);
	} else if (df > 0.0) {
		vec3 fp = ro + rd * df;
		vec3 boden = vec3(0.04, 0.028, 0.08);
		float abst = length(fp.xz - c.xz);
		boden *= 0.35 + 0.65 * smoothstep(0.25, 1.1, abst);
		// Spiegelung im Boden, zur Ferne hin schwächer.
		vec3 rr = reflect(rd, vec3(0.0, 1.0, 0.0));
		vec3 mr = marsch(fp + rr * 0.002, rr, c, a, g, yaw, 40, pw);
		vec3 sp = mr.x > 0.0 ? flaeche(fp + rr * mr.x, rr, c, a, g, yaw) : himmel(rr) * 0.6;
		boden += sp * 0.3 * exp(-df * 0.12);
		// Beim Aufsetzen ein Lichtring auf dem Boden, beim letzten Mal ein großer.
		for (int k = 0; k < 3; k++) {
			float tk = 0.5 + float(k) * 0.36;
			float s = t - tk;
			if (s > 0.0) {
				vec2 at = vec2(-3.0 + float(k + 1) * 2.0 * H, 0.0);
				float rad = s * (k == 2 ? 2.4 : 1.2);
				float stark = k == 2 ? 0.7 : 0.25;
				boden += vec3(0.6, 0.5, 1.0) * glanz(length(fp.xz - at) - rad, 0.04 + s * 0.06) * stark * exp(-s * 2.2);
			}
		}
		col = mix(boden, himmel(rd), 1.0 - exp(-df * df * 0.004));
	}
	// Rand des Würfels: knapp vorbei deckt anteilig (vor dem Boden).
	if (dw < 0.0 && mw.y > 0.0 && (df < 0.0 || mw.z < df)) {
		col = mix(col, flaeche(ro + rd * mw.z, rd, c, a, g, yaw), mw.y);
	}
	col *= e_out(t / 0.45);
	COLOR = vec4(fertig(col, UV, FRAGCOORD.xy, 0.5), 1.0);
}

// Spielhüllen im Spieleregal des Zimmers (MultiMesh, src/room/inhalt.gd): derselbe Kern wie die
// Hülle im Regal des Hauptmenüs (regal_huelle.gdshaderinc) – je Format und Region ein Material mit
// den Feldern des Rückens –, die Farbe des Titelfelds je Hülle in COLOR. Dazu die Abnutzung aus
// INSTANCE_CUSTOM.r (viel gespielt = abgegriffen: helle Scheuerstellen an den Kanten, matter, leicht
// ausgeblichen), INSTANCE_CUSTOM.b: Zufall je Spiel.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://src/room/shaders/rauschen.gdshaderinc"
#include "res://src/room/shaders/regal_huelle.gdshaderinc"

varying vec3 op;
varying vec3 on;
varying vec4 eigen;

void vertex() {
	op = VERTEX;
	on = NORMAL;
	eigen = INSTANCE_CUSTOM;
}

void fragment() {
	float rau;
	float spec;
	float cc;
	float ccr;
	vec3 c = uz_huelle(COLOR.rgb, op, on, 0.0, rau, spec, cc, ccr);
	float abn = eigen.r;
	vec3 t = (op + halb) / (2.0 * halb);
	// Abstand zum Rand der Fläche (ohne die Achse der Normale).
	vec3 d = min(t, 1.0 - t);
	vec3 an = abs(on);
	float rand = an.x > 0.5 ? min(d.y, d.z) : (an.y > 0.5 ? min(d.x, d.z) : min(d.x, d.y));
	// Nur an den Kanten und dezent: die Hülle bleibt die aus dem Hauptmenü.
	float n = uz_noise3(op * 160.0 + eigen.b * 37.0);
	float scheuer = smoothstep(0.05, 0.0, rand) * smoothstep(0.45, 0.85, n) * abn;
	float grau = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(grau), abn * 0.1);
	c = mix(c, vec3(0.7, 0.68, 0.65), clamp(scheuer, 0.0, 1.0) * 0.35);
	ALBEDO = c;
	ROUGHNESS = mix(rau, 0.55, abn * 0.4) + scheuer * 0.1;
	SPECULAR = spec;
	CLEARCOAT = cc * (1.0 - abn * 0.5);
	CLEARCOAT_ROUGHNESS = ccr;
}

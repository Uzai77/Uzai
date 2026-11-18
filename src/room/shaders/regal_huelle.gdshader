// Hülle im Regal (src/room/regal_welt.gd): eine Kiste mit leichter Fase, Rücken nach +z.
// Der Rücken trägt seine Farbe (Titelfeld: aus dem Cover bzw. fest nach Format, PS2 weiß) mit
// sanftem Verlauf (oben eine Spur heller, wie unter dem Licht der Leiste) und darüber die Felder
// der echten Aufmachung (Regal.ruecken_aufbau: PS2 PAL schwarzes PS-Feld, weißer PAL-Streifen,
// schwarzes Feld der Wortmarke; sonst ein Kopfband), unter dem Kopf eine feine Kante (kante 0:
// ohne). folie: Glanz der Folie über dem Rücken (PS2). Seiten und Kanten sind Kunststoff in der
// Farbe des Formats, oben und unten mit einem Schimmer (PS2 dunkelblau); art 1 (CD-Hülle) glänzt
// klar, art 2 (Karton) ist rundum bedruckt und matt. Die Vorderseite liegt als eigene Fläche auf +x
// (huelle_vorn.gdshader).
// Farben der Felder kommen linear (regal_welt.gd rechnet sie um, wie source_color es täte).
// Der Kern steht in regal_huelle.gdshaderinc (auch fürs Spieleregal im Zimmer).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 ruecken : source_color = vec3(0.3, 0.3, 0.32);
uniform float glimmen = 0.0;
// Bild des echten Rückens (ScreenScraper box-2D-side); quer: gedreht, von oben nach unten gelesen.
uniform sampler2D ruecken_bild : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool hat_ruecken = false;
uniform bool ruecken_quer = false;

#include "res://src/room/shaders/rauschen.gdshaderinc"
#include "res://src/room/shaders/regal_huelle.gdshaderinc"

varying vec3 op;
varying vec3 on;

void vertex() {
	op = VERTEX;
	on = NORMAL;
}

void fragment() {
	float rau;
	float spec;
	float cc;
	float ccr;
	vec3 c = uz_huelle(ruecken, op, on, glimmen, rau, spec, cc, ccr);
	if (hat_ruecken && on.z > 0.55) {
		vec2 t = (op.xy + halb.xy) / (2.0 * halb.xy);
		vec2 uv = ruecken_quer ? vec2(1.0 - t.y, 1.0 - t.x) : vec2(t.x, 1.0 - t.y);
		c = texture(ruecken_bild, uv).rgb * (1.0 - 0.22 * (1.0 - smoothstep(0.0, 0.16, min(t.x, 1.0 - t.x))));
		c += c * glimmen * 0.12;
	}
	ALBEDO = c;
	ROUGHNESS = rau;
	SPECULAR = spec;
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = ccr;
}

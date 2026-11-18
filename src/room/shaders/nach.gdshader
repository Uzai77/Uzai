// Nachbearbeitung im Zimmer (eigene, weil der Kompatibilitäts-Renderer weder SSAO noch
// Tiefenunschärfe kennt): dezente Umgebungsverdeckung aus der Tiefe, leichte Tiefenunschärfe um
// den Blickpunkt und ein unsichtbares, ruhendes Rauschen gegen Stufen in dunklen Verläufen. Wie viele Proben,
// gibt die Qualitätsstufe vor (ao_proben, dof_proben; licht.gd). Die Vignette liegt in 2D darüber
// (zimmer_welt.gd), damit es sie auch in der Stufe Leicht ohne diesen Durchgang gibt.
// Liegt als Fläche vor der Kamera und wird als erstes durchsichtiges Teil gezeichnet – Schrift im
// Zimmer (Hüllen, Pokale) bleibt darüber scharf.
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D tiefe : hint_depth_texture, filter_nearest;
uniform sampler2D farbe : hint_screen_texture, filter_linear;
uniform float fokus = 3.0;        // Entfernung, die scharf ist (Meter)
uniform float fokus_tiefe = 1.6;  // so weit davor und dahinter bleibt es scharf
uniform float unschaerfe = 4.0;   // höchstens so viele Bildpunkte (bei 1080 Zeilen)
uniform float ao_staerke = 0.55;
uniform float ao_radius = 0.32;   // Meter
uniform int ao_proben = 12;       // 0 … 12
uniform int dof_proben = 16;      // 0 … 16
uniform float korn = 0.0;         // feines Filmkorn (Forward+: ein Hauch, 0 aus)

// Lineare Tiefe (Meter) aus dem Wert im Tiefenpuffer.
float lin(float d, vec2 uv, mat4 inv) {
	vec4 v = inv * vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
	return -v.z / v.w;
}

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float k = VIEWPORT_SIZE.y / 1080.0;
	float z = lin(texture(tiefe, uv).r, uv, INV_PROJECTION_MATRIX);
	// Tiefenunschärfe: Kreis aus 16 Proben (goldener Winkel), Radius nach Abstand vom Fokus.
	float coc = clamp((abs(z - fokus) - fokus_tiefe) / max(fokus * 0.9, 0.5), 0.0, 1.0) * unschaerfe * k;
	vec3 c = texture(farbe, uv).rgb;
	if (coc > 0.4 && dof_proben > 1) {
		vec3 sum = c;
		float wsum = 1.0;
		float nd = float(dof_proben - 1);
		for (int i = 1; i < 16; i++) {
			if (i >= dof_proben) {
				break;
			}
			float a = float(i) * 2.39996;
			float r = sqrt(float(i) / nd) * coc;
			vec2 o = vec2(cos(a), sin(a)) * r * px;
			float zs = lin(texture(tiefe, uv + o).r, uv + o, INV_PROJECTION_MATRIX);
			// Nähere Dinge im Fokus bluten nicht in den unscharfen Hintergrund.
			float w = zs < z - 0.3 && abs(zs - fokus) < fokus_tiefe ? 0.15 : 1.0;
			sum += texture(farbe, uv + o).rgb * w;
			wsum += w;
		}
		c = sum / wsum;
	}
	// Umgebungsverdeckung: 12 Proben in einer Scheibe (Radius in Metern, auf den Bildschirm
	// umgerechnet), je Bildpunkt gedreht; nur Nachbarn knapp davor verdecken (Bereichsprüfung).
	if (ao_staerke > 0.0 && ao_proben > 0 && z < 40.0) {
		float na = float(ao_proben);
		float rpx = clamp(ao_radius * PROJECTION_MATRIX[1][1] * 0.5 * VIEWPORT_SIZE.y / max(z, 0.1), 3.0, 70.0 * k);
		float rot = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715)))) * 6.2831;
		float occ = 0.0;
		for (int i = 0; i < 12; i++) {
			if (i >= ao_proben) {
				break;
			}
			float a = float(i) * 2.39996 + rot;
			float r = (float(i) + 0.5) / na;
			vec2 o = vec2(cos(a), sin(a)) * r * rpx * px;
			float zs = lin(texture(tiefe, uv + o).r, uv + o, INV_PROJECTION_MATRIX);
			float diff = z - zs;
			occ += smoothstep(0.015, 0.08, diff) * (1.0 - smoothstep(ao_radius * 0.8, ao_radius * 2.2, diff));
		}
		c *= 1.0 - ao_staerke * pow(occ / na, 1.2);
	}
	// Rauschen gegen Stufen: fest je Bildpunkt (nicht je Bild – das flimmerte) und nur so stark wie
	// eine Stufe im fertigen Bild; die Farbe hier ist noch linear (vor Belichtung und Tonemapping),
	// darum auf die Helligkeit gerechnet (sonst wäre es in dunklen Flächen ein sichtbares Korn).
	float rn = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	// Korn wie auf Film: in den Mitten am stärksten, in Lichtern und Schatten kaum.
	float hellig = dot(c, vec3(0.3, 0.59, 0.11));
	float stufe = 2.2 * pow(max(hellig, 0.0005), 0.545) / 255.0;
	c += (rn - 0.5) * (stufe + korn * 4.0 * hellig * (1.0 - hellig));
	ALBEDO = c;
}

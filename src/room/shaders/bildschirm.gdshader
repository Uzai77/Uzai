// Bildschirm des Fernsehers: art 0 Röhre (Wölbung, Zeilen, Schattenmaske, dunkle Ecken),
// 1 Flachbild (klar, dunkles Glas mit Spiegelung), 2 Beamer (weiche, helle Leinwand, Licht fällt
// zur Mitte hin). an: 0 aus … 1 an. bild: was der Fernseher zeigt (eigene Uzai-Ansicht oder das
// laufende Spiel). einschalten: 0 … 1 beim Einschalten – die Röhre zieht eine helle Linie auf, die
// sich nach oben und unten öffnet; Flachbild und Beamer blenden mit einem weichen Aufleuchten auf.
//
// Das Bild soll im Zimmer so aussehen wie das Original: Eingeschaltet nimmt die Fläche kein Licht
// an (keine Lampen, Spiegelungen, Umgebungslicht, kein Nebel), und ihr Leuchten gleicht aus, was
// die Engine danach mit dem ganzen Bild macht – Belichtung, Tonemapping (AgX bzw. Filmic), Kontrast,
// Sättigung und Farbkorrektur rückwärts (Werte aus raum.gd, gesetzt von zimmer_welt.gd tv_ton).
// Nur das Glühen der Engine lässt sich so nicht ausgleichen: Das Leuchten bleibt knapp unter seiner
// Schwelle (grenze), die hellsten Stellen werden dafür gleichmäßig etwas gedämpft.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, fog_disabled;

// Ohne source_color: Die Werte bleiben sRGB, wie das Original sie hat (Umrechnung unten).
uniform sampler2D bild : hint_default_black, filter_linear_mipmap;
uniform int art = 1;
uniform float an = 1.0;
uniform float hell = 1.0;
uniform float zeilen = 240.0;
uniform float einschalten = 1.0;
// Ausgleich der Nachbearbeitung: ton 0 linear (nichts), 2 Filmic, 4 AgX (Kennungen der Engine).
uniform int ton = 0;
uniform float weiss = 1.0;
uniform float belichtung = 1.0;
uniform float kontrast = 1.0;
uniform float saettigung = 1.0;
uniform bool lut_an = false;
uniform sampler2D lut_umkehr : filter_linear, repeat_disable;
uniform float grenze = 100.0;

// AgX der Engine rückwärts: Matrizen umgekehrt (aus tonemap.glsl), die Kurve per Halbierung.
const mat3 AGX_EIN_UMKEHR = mat3(vec3(2.114111984, -0.370516020, -0.165946406), vec3(-1.027221657, 1.552988351, -0.254760874),
		vec3(-0.087064926, -0.182427712, 1.420779648));
const mat3 AGX_AUS_UMKEHR = mat3(vec3(0.570872291, 0.130640051, 0.089083978), vec3(0.377607644, 0.842927617, 0.187409541),
		vec3(0.051599157, 0.026415619, 0.723461317));
const float AGX_MIN_EV = -12.4739311883324;
const float AGX_MAX_EV = 4.02606881166759;

vec3 zu_linear(vec3 s) {
	s = clamp(s, 0.0, 1.0);
	return mix(pow((s + 0.055) / 1.055, vec3(2.4)), s / 12.92, step(s, vec3(0.04045)));
}

vec3 zu_srgb(vec3 l) {
	l = clamp(l, 0.0, 1.0);
	return mix(1.055 * pow(l, vec3(1.0 / 2.4)) - 0.055, l * 12.92, step(l, vec3(0.0031308)));
}

vec3 agx_kurve(vec3 x) {
	vec3 x2 = x * x;
	vec3 x4 = x2 * x2;
	return 0.021 * x + 4.0111 * x2 - 25.682 * x2 * x + 70.359 * x4 - 74.778 * x4 * x + 27.069 * x4 * x2;
}

vec3 agx_umkehr(vec3 y) {
	vec3 v = pow(max(AGX_AUS_UMKEHR * y, vec3(0.0)), vec3(1.0 / 2.4));
	vec3 lo = vec3(0.0);
	vec3 hi = vec3(1.0);
	for (int i = 0; i < 16; i++) {
		vec3 m = (lo + hi) * 0.5;
		vec3 drunter = step(agx_kurve(m), v);
		lo = mix(lo, m, drunter);
		hi = mix(m, hi, drunter);
	}
	vec3 x = (lo + hi) * 0.5;
	return max(AGX_EIN_UMKEHR * exp2(x * (AGX_MAX_EV - AGX_MIN_EV) + AGX_MIN_EV), vec3(0.0));
}

// Filmic der Engine (Hable, exposure_bias 2) rückwärts: je Kanal eine quadratische Gleichung.
vec3 filmic_umkehr(vec3 y) {
	const float FA = 0.88;
	const float FB = 0.6;
	const float FC = 0.1;
	const float FD = 0.2;
	const float FE = 0.01;
	const float FF = 0.3;
	float w = ((weiss * (FA * weiss + FC * FB) + FD * FE) / (weiss * (FA * weiss + FB) + FD * FF)) - FE / FF;
	vec3 t = min(y * w + FE / FF, vec3(0.9999));
	vec3 a = FA * (1.0 - t);
	vec3 b = FB * (FC - t);
	vec3 c = FD * (FE - t * FF);
	return max((-b + sqrt(max(b * b - 4.0 * a * c, vec3(0.0)))) / (2.0 * a), vec3(0.0));
}

// Was die Fläche leuchten muss, damit am Ende d (linear, 0 … 1) auf dem Bildschirm steht.
vec3 ausgleich(vec3 d) {
	vec3 s = zu_srgb(d);
	if (lut_an) {
		s = vec3(texture(lut_umkehr, vec2(s.r, 0.5)).r, texture(lut_umkehr, vec2(s.g, 0.5)).g, texture(lut_umkehr, vec2(s.b, 0.5)).b);
	}
	// Die Engine: erst Kontrast um 0,5, dann Sättigung um den Mittelwert – hier umgekehrt.
	float mitte = dot(s, vec3(0.33333));
	s = mitte + (s - mitte) / max(saettigung, 0.01);
	s = 0.5 + (s - 0.5) / max(kontrast, 0.01);
	vec3 l = zu_linear(s);
	if (ton == 4) {
		l = agx_umkehr(l);
	} else if (ton == 2) {
		l = filmic_umkehr(l);
	}
	l /= max(belichtung, 0.01);
	float spitze = max(l.r, max(l.g, l.b));
	return spitze > grenze ? l * (grenze / spitze) : l;
}

void fragment() {
	vec2 uv = UV;
	if (art == 0) {
		vec2 cc = uv - 0.5;
		float r2 = dot(cc, cc);
		uv = 0.5 + cc * (1.0 + r2 * 0.22);
	}
	vec3 c = zu_linear(texture(bild, clamp(uv, 0.0, 1.0)).rgb);
	float innen = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	if (art == 0) {
		float z = 0.72 + 0.28 * sin(uv.y * zeilen * 3.14159);
		float maske = 0.86 + 0.14 * sin(FRAGCOORD.x * 2.094);
		vec2 cc = uv - 0.5;
		float vig = 1.0 - smoothstep(0.18, 0.62, length(cc * vec2(1.0, 1.15)));
		c *= z * maske * (0.45 + 0.55 * vig) * 1.15;
	} else if (art == 2) {
		vec2 cc = UV - 0.5;
		float fall = 1.0 - 0.4 * smoothstep(0.1, 0.75, length(cc));
		c = mix(vec3(0.07), c, 0.88) * fall;
	}
	c *= innen;
	if (einschalten < 0.999) {
		float e = clamp(einschalten, 0.0, 1.0);
		if (art == 0) {
			// Erst ein heller Punkt, der zur Linie wird, dann öffnet sie sich mit weichen Kanten.
			float breit = smoothstep(0.0, 0.16, e);
			float hoch = mix(0.005, 0.52, smoothstep(0.14, 0.62, e));
			float band = (1.0 - smoothstep(hoch - 0.012, hoch, abs(UV.y - 0.5))) * (1.0 - smoothstep(0.5 * breit - 0.03, 0.5 * breit, abs(UV.x - 0.5)));
			float blitz = (1.0 - smoothstep(0.08, 0.5, e)) * 1.3;
			c = (c * smoothstep(0.2, 0.75, e) + vec3(0.95, 0.97, 1.0) * blitz) * band;
		} else {
			// Flachbild und Beamer: ein kurzes, weiches Aufleuchten in der Mitte, dann das Bild.
			float auf = smoothstep(0.12, 0.8, e);
			vec2 cc = (UV - 0.5) * vec2(1.0, 1.6);
			float glanz = exp(-dot(cc, cc) * 14.0) * (1.0 - smoothstep(0.1, 0.6, e)) * smoothstep(0.0, 0.1, e) * 0.5;
			c = c * auf + vec3(0.8, 0.85, 1.0) * glanz;
		}
	}
	// Ausgeschaltet: dunkles Glas bzw. Leinwand, die das Licht im Raum annimmt; eingeschaltet nicht.
	float licht = 1.0 - clamp(an, 0.0, 1.0);
	if (art == 2) {
		ALBEDO = vec3(0.86) * licht;
		ROUGHNESS = 0.95;
		SPECULAR = 0.1 * licht;
	} else {
		ALBEDO = vec3(0.012) * licht;
		ROUGHNESS = art == 0 ? 0.18 : 0.1;
		SPECULAR = 0.6 * licht;
	}
	EMISSION = ausgleich(clamp(c * hell, 0.0, 1.0)) * an;
}

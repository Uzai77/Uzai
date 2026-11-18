// Stoff (stoff.gdshader, stoff_wehen.gdshader): feines Gewebe, weicher Samtschimmer an den Kanten,
// keine harten Glanzlichter. Mit WEHEN bewegt sich der Saum im Luftzug (Vorhänge).
#include "res://src/room/shaders/rauschen.gdshaderinc"
#include "res://src/room/shaders/lichter.gdshaderinc"
#include "res://src/room/shaders/muster.gdshaderinc"

uniform vec3 farbe : source_color = vec3(0.55, 0.6, 0.5);
uniform float webung = 140.0;
uniform float schimmer = 0.32;
uniform float leuchten = 0.0;
uniform vec3 licht : source_color = vec3(1.0, 0.72, 0.42);
uniform float flor = 0.0;   // Teppich: gröbere, unruhigere Fasern
uniform sampler2D ao_karte : hint_default_white, filter_linear;   // Teppich: Kontaktschatten der Möbel
uniform vec2 ao_raum = vec2(0.0);
// Anpassen (gestalt.gd): Muster aus muster.gdshaderinc in muster_farbe; glanz für Leder und Samt.
uniform int muster = 0;
uniform vec3 muster_farbe : source_color = vec3(0.93, 0.9, 0.84);
uniform float muster_mass = 1.0;
uniform float glanz = 0.0;
// Gewebe als Karte (stoffe.gd _stoff_karte): Normale und Rauheit, Kachel t_mass Meter (UV in Metern).
uniform sampler2D t_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_rau : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float t_mass = 0.22;
uniform float t_rau_mittel = 0.9;
uniform float t_staerke = 1.0;

uniform float wehen = 0.0;         // Vorhang: sanftes Wehen im Luftzug (Meter am Saum, 0 = still)
uniform float wehen_hoehe = 2.4;   // Höhe des Vorhangs (oben hängt er fest, unten weht er)

varying vec3 wp;

void vertex() {
#ifdef WEHEN
	if (wehen > 0.0) {
		float t = clamp(1.0 - VERTEX.y / wehen_hoehe, 0.0, 1.0);
		float ph = TIME * 0.6 + VERTEX.x * 2.2 + float(INSTANCE_ID) * 1.7;
		VERTEX.z += (sin(ph) * 0.6 + sin(ph * 2.3 + 1.0) * 0.4) * wehen * t * t;
		VERTEX.x += cos(ph * 0.7) * wehen * 0.25 * t * t;
	}
#endif
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * webung;
	// Webung und Fasern nur, solange ein Bildpunkt sie auflöst: feiner flimmerten sie (Moiré), bei den
	// wehenden Vorhängen am Fenster ständig.
	float scharf = 1.0 - smoothstep(0.2, 0.5, max(fwidth(uv.x), fwidth(uv.y)));
	float w = 0.5 + 0.5 * sin(uv.x * 6.2831) * sin(uv.y * 6.2831) * scharf;
	float n = uz_noise2(UV * 9.0);
	vec2 fuv = UV * (webung * 0.9 + flor * 80.0);
	float f = mix(0.5, uz_noise2(fuv), 1.0 - smoothstep(0.3, 0.8, max(fwidth(fuv.x), fwidth(fuv.y))));
	vec3 grund = farbe;
	if (muster > 0) {
		grund = mix(farbe, muster_farbe, uz_muster(UV, muster, muster_mass));
	}
	vec3 c = grund * (0.9 + 0.07 * w + 0.08 * (n - 0.5) + flor * 0.18 * (f - 0.5));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	c += grund * fres * schimmer;
	vec3 eigen_licht = vec3(0.0);
	if (ao_raum.x > 0.0) {
		// Teppich: liegt wie der Boden auf der Hülle – Lampen und Sonnenfleck aus dem Shader.
		c *= texture(ao_karte, wp.xz / ao_raum).r;
		vec3 hoch = vec3(0.0, 1.0, 0.0);
		eigen_licht = c * (uz_lampen(wp + hoch * 0.01, hoch) + uz_fleck(wp, hoch));
	}
	ALBEDO = c * COLOR.rgb;
	EMISSION = eigen_licht;
	vec2 tuv = UV / t_mass;
	NORMAL_MAP = texture(t_normal, tuv).xyz;
	// Feine Gewebe-Normalen nur, solange ein Bildpunkt höchstens wenige Texel der Karte deckt: weiter
	// weg sprangen die Glanzpunkte von Bildpunkt zu Bildpunkt – auf dem wehenden Vorhang flimmerte das
	// ständig (aus der Entfernung sieht man das Gewebe ohnehin nicht).
	float texel = max(length(dFdx(tuv)), length(dFdy(tuv))) * float(textureSize(t_normal, 0).x);
	NORMAL_MAP_DEPTH = t_staerke * (1.0 - smoothstep(1.5, 5.0, texel));
	ROUGHNESS = clamp(mix(0.92, 0.42, glanz) * texture(t_rau, tuv).r / max(t_rau_mittel, 0.05), 0.05, 1.0);
	SPECULAR = mix(0.18, 0.45, glanz);
	if (leuchten > 0.0) {
		float innen = 0.65 + 0.35 * (1.0 - fres);
		EMISSION += licht * farbe * leuchten * innen;
	}
}

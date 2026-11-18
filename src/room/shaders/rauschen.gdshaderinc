// Gemeinsames Rauschen für die Zimmer-Shader (Wertrauschen, eigene Fassung).
float uz_hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float uz_hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float uz_noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(uz_hash3(i), uz_hash3(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(uz_hash3(i + vec3(0.0, 1.0, 0.0)), uz_hash3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(uz_hash3(i + vec3(0.0, 0.0, 1.0)), uz_hash3(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(uz_hash3(i + vec3(0.0, 1.0, 1.0)), uz_hash3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float uz_noise2(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(uz_hash2(i), uz_hash2(i + vec2(1.0, 0.0)), f.x),
		mix(uz_hash2(i + vec2(0.0, 1.0)), uz_hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

float uz_fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * uz_noise2(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

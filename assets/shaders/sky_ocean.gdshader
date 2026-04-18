shader_type sky;
// Anime-style ocean sky: deep blue gradient, wispy high clouds, horizon shimmer.

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i),            hash21(i + vec2(1, 0)), f.x),
	           mix(hash21(i + vec2(0,1)), hash21(i + vec2(1,1)), f.x), f.y);
}

void sky() {
	vec3 d = normalize(POSITION);
	float h = d.y;

	// Sky gradient: light sky-blue horizon → rich ocean-blue zenith
	vec3 col = mix(vec3(0.52, 0.74, 0.95),
	               vec3(0.10, 0.28, 0.72),
	               clamp(pow(max(h, 0.0), 0.48), 0.0, 1.0));

	// Below horizon: deep dark ocean
	col = mix(vec3(0.08, 0.16, 0.28), col, smoothstep(-0.22, 0.04, h));

	// Ocean shimmer band at horizon (animates fast for water glints)
	float band = exp(-abs(h + 0.02) * 30.0);
	vec2 wuv = d.xz * 14.0 + vec2(TIME * 0.28, TIME * 0.14);
	float shimmer = vnoise(wuv) * 0.6 + vnoise(wuv * 2.5 + vec2(1.3, 2.7)) * 0.4;
	col += vec3(0.65, 0.85, 1.0) * shimmer * band * 0.55;

	// Thin wispy cirrus clouds high up
	if (h > 0.06) {
		float inv_y = 1.0 / max(h, 0.06);
		vec2 uv = d.xz * inv_y * 0.18 + vec2(TIME * 0.0035, TIME * 0.0008);
		float c = vnoise(uv * 2.0)           * 0.55
		        + vnoise(uv * 5.0 + vec2(2.1, 3.3)) * 0.30
		        + vnoise(uv * 10.0 + vec2(4.4, 1.8)) * 0.15;
		c = smoothstep(0.60, 0.80, c) * smoothstep(0.06, 0.22, h) * 0.65;
		col = mix(col, vec3(0.88, 0.92, 1.0), c);
	}

	// Cool sun / reflected glare
	vec3 sun_dir = normalize(vec3(-0.30, 0.62, 0.72));
	float s = dot(d, sun_dir);
	col += vec3(0.88, 0.92, 1.00) * pow(max(s, 0.0), 90.0) * 1.6;
	col += vec3(0.68, 0.78, 1.00) * pow(max(s, 0.0), 8.0)  * 0.10;

	COLOR = col;
}

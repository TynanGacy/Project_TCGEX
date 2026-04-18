shader_type sky;
// Anime-style meadow sky: clear blue gradient with animated puffy clouds and warm sun.

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i),          hash21(i + vec2(1, 0)), f.x),
	           mix(hash21(i + vec2(0,1)), hash21(i + vec2(1,1)), f.x), f.y);
}

void sky() {
	vec3 d = normalize(POSITION);
	float h = d.y;

	// Sky gradient: pale blue horizon → deep blue zenith
	vec3 col = mix(vec3(0.68, 0.84, 0.98),
	               vec3(0.28, 0.50, 0.92),
	               clamp(pow(max(h, 0.0), 0.55), 0.0, 1.0));

	// Below horizon: soft green-white (distant meadow)
	col = mix(vec3(0.72, 0.82, 0.65), col, smoothstep(-0.18, 0.06, h));

	// Animated puffy clouds (only in the upper sky)
	if (h > 0.01) {
		float inv_y = 1.0 / max(h, 0.04);
		vec2 uv = d.xz * inv_y * 0.25 + vec2(TIME * 0.005, 0.0);
		float c = vnoise(uv * 2.0)        * 0.55
		        + vnoise(uv * 4.2 + vec2(3.1, 1.7)) * 0.30
		        + vnoise(uv * 8.5 + vec2(5.2, 3.1)) * 0.15;
		c = smoothstep(0.52, 0.73, c) * smoothstep(0.01, 0.14, h);
		// Cloud shadow tint on underside
		vec3 cloud_col = mix(vec3(0.84, 0.86, 0.90), vec3(0.98, 0.98, 1.0), c);
		col = mix(col, cloud_col, c * 0.88);
	}

	// Sun disc and atmospheric glow
	vec3 sun_dir = normalize(vec3(0.4, 0.72, -0.55));
	float s = dot(d, sun_dir);
	col += vec3(1.00, 0.96, 0.72) * pow(max(s, 0.0), 80.0) * 1.4;
	col += vec3(1.00, 0.88, 0.60) * pow(max(s, 0.0), 10.0) * 0.14;

	COLOR = vec4(col, 1.0);
}

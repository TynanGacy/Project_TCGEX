shader_type sky;
// Anime-style volcanic sky: dark ashen purple zenith, fiery orange horizon,
// drifting ash wisps, and scattered ember sparks.

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

	// Sky gradient: fiery orange horizon → dark ashen purple zenith
	vec3 col = mix(vec3(0.88, 0.28, 0.04),
	               vec3(0.11, 0.07, 0.13),
	               clamp(pow(max(h, 0.0), 0.38), 0.0, 1.0));

	// Below horizon: dark volcanic rock
	col = mix(vec3(0.16, 0.05, 0.02), col, smoothstep(-0.28, 0.04, h));

	// Drifting ash / smoke wisps
	{
		float inv_y = 1.0 / max(abs(h) + 0.06, 0.06);
		vec2 uv = d.xz * inv_y * 0.32;
		uv.x += TIME * 0.010;
		uv.y += TIME * 0.003;
		float ash = vnoise(uv * 1.4)           * 0.50
		          + vnoise(uv * 3.1 + vec2(1.7, 0.8)) * 0.30
		          + vnoise(uv * 6.2 + vec2(3.3, 2.1)) * 0.20;
		float ash_mask = smoothstep(0.50, 0.70, ash)
		               * (0.35 + 0.45 * smoothstep(-0.12, 0.35, h));
		col = mix(col, vec3(0.22, 0.14, 0.12), ash_mask * 0.65);
	}

	// Ember sparks — rising fast noise points near the horizon
	{
		vec2 euv = d.xz / max(abs(d.y) + 0.05, 0.05);
		euv += vec2(TIME * 0.04, -TIME * 0.12);
		float em = vnoise(euv * 6.0) * vnoise(euv * 12.0 + vec2(2.3, 1.1));
		em = pow(em, 2.8) * max(1.0 - h * 2.5, 0.0) * 18.0;
		col += vec3(1.0, 0.42, 0.08) * clamp(em, 0.0, 1.0);
	}

	// Volcanic glow at base — warm orange band hugging the horizon
	float vol = exp(-abs(h + 0.04) * 9.0) * exp(-d.x * d.x * 1.5);
	col += vec3(1.0, 0.32, 0.00) * vol * 0.55;

	COLOR = col;
}

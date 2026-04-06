// Spatial shader for the card face mesh.
// Samples the face viewport texture with mirrored UV at the corner regions,
// then clips to a rounded rectangle matching the card_back silhouette.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D face_texture : source_color;

// Corner radius in world units, calibrated against card_back.png:
//   left edge first opaque at y=27/1044 -> R = 0.88 * 27/1044 ≈ 0.0228
//   top edge first opaque at x=29/749  -> R = 0.63 * 29/749  ≈ 0.0244
uniform float corner_radius : hint_range(0.0, 0.1) = 0.023;

// Physical card size in world units (must match Card.CARD_WIDTH / CARD_HEIGHT).
uniform vec2 card_size = vec2(0.63, 0.88);

// Reflect UV into the interior when the sample point is inside a corner region.
// ru/rv are the corner extents expressed as UV fractions.
vec2 mirror_corners(vec2 uv, float ru, float rv) {
	vec2 m = uv;
	if (m.x < ru)            m.x = 2.0 * ru - m.x;
	else if (m.x > 1.0 - ru) m.x = 2.0 * (1.0 - ru) - m.x;
	if (m.y < rv)            m.y = 2.0 * rv - m.y;
	else if (m.y > 1.0 - rv) m.y = 2.0 * (1.0 - rv) - m.y;
	return m;
}

void fragment() {
	float r  = corner_radius;
	float ru = r / card_size.x;  // corner extent in U
	float rv = r / card_size.y;  // corner extent in V

	// Sample texture, mirroring into the card interior near each corner so
	// the content at the rounded edge reads as a natural reflection of the
	// adjacent card border rather than a hard cut-off.
	vec2 sample_uv = mirror_corners(UV, ru, rv);
	vec4 color = texture(face_texture, sample_uv);
	ALBEDO = color.rgb;

	// Rounded-rectangle SDF in world space for a clean, aspect-correct clip.
	vec2 p = (UV - 0.5) * card_size;          // centred world-space position
	vec2 q = abs(p) - (card_size * 0.5 - r);
	float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;

	// Hard clip matching card_back alpha-scissor behaviour.
	ALPHA = sdf < 0.0 ? 1.0 : 0.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}

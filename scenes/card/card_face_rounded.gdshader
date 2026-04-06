// Spatial shader for the card face mesh.
// Samples the face viewport texture with mirrored UV at the corner regions,
// then clips to a rounded rectangle matching the card_back silhouette.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D face_texture : source_color;

// Corner radius for the SDF clip, in world units.
// Calibrated against card_back.png:
//   left edge first opaque at y=27/1044 -> R = 0.88 * 27/1044 ≈ 0.0228
//   top edge first opaque at x=29/749  -> R = 0.63 * 29/749  ≈ 0.0244
uniform float corner_radius : hint_range(0.0, 0.1) = 0.023;

// Mirror zone radius in world units.  Should be larger than corner_radius so
// the mirror source points land inside the card's yellow border rather than in
// the white scan-background area at the physical card's rounded corners.
// A good starting value is the physical card corner: ~3.175 mm on a 63 mm wide
// card → 0.032 world units.  Adjust if card scans have a wider/narrower margin.
uniform float mirror_radius : hint_range(0.0, 0.15) = 0.032;

// Physical card size in world units (must match Card.CARD_WIDTH / CARD_HEIGHT).
uniform vec2 card_size = vec2(0.63, 0.88);

// Reflect UV into the interior only when the sample point is in a corner region
// (near both a horizontal AND vertical edge simultaneously).  Using a mirror
// radius larger than the SDF clip radius ensures the reflected content is drawn
// from well inside the yellow border, not from the white scan-background corner.
vec2 mirror_corners(vec2 uv, float mru, float mrv) {
	vec2 m = uv;
	bool near_x = (m.x < mru) || (m.x > 1.0 - mru);
	bool near_y = (m.y < mrv) || (m.y > 1.0 - mrv);
	if (near_x && near_y) {
		if (m.x < mru)            m.x = 2.0 * mru - m.x;
		else if (m.x > 1.0 - mru) m.x = 2.0 * (1.0 - mru) - m.x;
		if (m.y < mrv)            m.y = 2.0 * mrv - m.y;
		else if (m.y > 1.0 - mrv) m.y = 2.0 * (1.0 - mrv) - m.y;
	}
	return m;
}

void fragment() {
	float r   = corner_radius;
	float ru  = r / card_size.x;            // SDF corner extent in U
	float rv  = r / card_size.y;            // SDF corner extent in V
	float mru = mirror_radius / card_size.x; // mirror zone extent in U
	float mrv = mirror_radius / card_size.y; // mirror zone extent in V

	// Sample texture, mirroring at corners so the rounded edge blends into the
	// card border rather than exposing white scan-background or a hard cut-off.
	vec2 sample_uv = mirror_corners(UV, mru, mrv);
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

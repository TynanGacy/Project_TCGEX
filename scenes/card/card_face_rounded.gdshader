// Spatial shader for the card face mesh.
// Fits the rectangular card image inside the rounded card shape without
// cropping: the image corners sit exactly on the arc at 45°, leaving a thin
// gap band along each straight edge.  Those bands are filled by mirroring the
// image's edge content outward.  The card is then clipped to the rounded
// rectangle with an SDF.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D face_texture : source_color;

// Corner radius in world units, calibrated against card_back.png:
//   left edge first opaque at y=27/1044 -> R = 0.88 * 27/1044 ≈ 0.0228
//   top edge first opaque at x=29/749  -> R = 0.63 * 29/749  ≈ 0.0244
uniform float corner_radius : hint_range(0.0, 0.1) = 0.023;

// Physical card size in world units (must match Card.CARD_WIDTH / CARD_HEIGHT).
uniform vec2 card_size = vec2(0.63, 0.88);

void fragment() {
	float r = corner_radius;

	// Gap between each card edge and the inscribed rectangle's edge.
	// Derived from the inscribed-rectangle geometry: a rect whose corners
	// sit on the corner arcs has edges inset by  r * (1 - 1/sqrt(2)).
	// 1 - 1/sqrt(2) ≈ 0.29289
	float gap_u = r * 0.29289 / card_size.x;
	float gap_v = r * 0.29289 / card_size.y;

	// Mirror the image outward into each edge gap band independently.
	// Applying x and y corrections separately (not corner-only) ensures the
	// full straight-edge band is filled on all four sides.
	vec2 uv = UV;
	if      (uv.x < gap_u)            uv.x = 2.0 * gap_u - uv.x;
	else if (uv.x > 1.0 - gap_u)      uv.x = 2.0 * (1.0 - gap_u) - uv.x;
	if      (uv.y < gap_v)            uv.y = 2.0 * gap_v - uv.y;
	else if (uv.y > 1.0 - gap_v)      uv.y = 2.0 * (1.0 - gap_v) - uv.y;

	vec4 color = texture(face_texture, uv);
	ALBEDO = color.rgb;

	// Rounded-rectangle SDF in world space for a clean, aspect-correct clip.
	vec2 p = (UV - 0.5) * card_size;
	vec2 q = abs(p) - (card_size * 0.5 - r);
	float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;

	// Hard clip matching card_back alpha-scissor behaviour.
	ALPHA = sdf < 0.0 ? 1.0 : 0.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}

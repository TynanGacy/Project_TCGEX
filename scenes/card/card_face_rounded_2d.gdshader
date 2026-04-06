// canvas_item shader for the card-art TextureRect in the right-click popup.
// Mirrors content only at the four corner regions (same logic as the spatial
// card_face_rounded.gdshader), then clips to a rounded rectangle that matches
// the card silhouette seen on the 3D table.
shader_type canvas_item;

// Physical card dimensions in world units — must match Card.CARD_WIDTH/HEIGHT.
uniform vec2 card_size = vec2(0.63, 0.88);

// Corner radius in world units — must match the spatial shader value.
uniform float corner_radius : hint_range(0.0, 0.1) = 0.023;

// Mirror UV only when the sample point is near both a horizontal and vertical
// edge (i.e. inside an actual corner region that the rounded clip will cut off).
vec2 mirror_corners(vec2 uv, float ru, float rv) {
	vec2 m = uv;
	bool near_x = (m.x < ru) || (m.x > 1.0 - ru);
	bool near_y = (m.y < rv) || (m.y > 1.0 - rv);
	if (near_x && near_y) {
		if (m.x < ru)            m.x = 2.0 * ru - m.x;
		else if (m.x > 1.0 - ru) m.x = 2.0 * (1.0 - ru) - m.x;
		if (m.y < rv)            m.y = 2.0 * rv - m.y;
		else if (m.y > 1.0 - rv) m.y = 2.0 * (1.0 - rv) - m.y;
	}
	return m;
}

void fragment() {
	float ru = corner_radius / card_size.x;
	float rv = corner_radius / card_size.y;

	vec2 uv = mirror_corners(UV, ru, rv);
	COLOR = texture(TEXTURE, uv);

	// Rounded-rectangle SDF in world-space coords (identical to spatial shader).
	vec2 p = (UV - 0.5) * card_size;
	vec2 q = abs(p) - (card_size * 0.5 - corner_radius);
	float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - corner_radius;
	COLOR.a *= (sdf < 0.0 ? 1.0 : 0.0);
}

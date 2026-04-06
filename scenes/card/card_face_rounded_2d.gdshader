// canvas_item shader for the card-art TextureRect in the right-click popup.
// Mirrors content only at the four corner regions (same logic as the spatial
// card_face_rounded.gdshader), then clips to a rounded rectangle that matches
// the card silhouette seen on the 3D table.
shader_type canvas_item;

// Physical card dimensions in world units — must match Card.CARD_WIDTH/HEIGHT.
uniform vec2 card_size = vec2(0.63, 0.88);

// Corner radius for the SDF clip — must match the spatial shader value.
uniform float corner_radius : hint_range(0.0, 0.1) = 0.023;

// Mirror zone radius — must match the spatial shader value.
// Larger than corner_radius so the mirror source is inside the yellow border.
uniform float mirror_radius : hint_range(0.0, 0.15) = 0.032;

// Mirror UV only when the sample point is near both a horizontal and vertical
// edge (i.e. inside an actual corner region).  The mirror zone is intentionally
// wider than the SDF clip so the reflected content comes from the card's border
// rather than the white scan-background at the physical card's rounded corners.
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
	float mru = mirror_radius / card_size.x;
	float mrv = mirror_radius / card_size.y;

	vec2 uv = mirror_corners(UV, mru, mrv);
	COLOR = texture(TEXTURE, uv);

	// Rounded rect SDF in world-space coords (identical to spatial shader).
	float r   = corner_radius;
	vec2  p   = (UV - 0.5) * card_size;
	vec2  q   = abs(p) - (card_size * 0.5 - r);
	float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
	COLOR.a  *= (sdf < 0.0 ? 1.0 : 0.0);
}

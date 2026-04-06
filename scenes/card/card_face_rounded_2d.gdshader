// canvas_item shader for the card-art TextureRect in the right-click popup.
// Uses the same inscribed-rectangle edge-mirroring logic as the spatial shader,
// then clips to a matching rounded rectangle.
shader_type canvas_item;

// Physical card dimensions in world units — must match Card.CARD_WIDTH/HEIGHT.
uniform vec2 card_size = vec2(0.63, 0.88);

// Corner radius — must match the spatial shader value.
uniform float corner_radius : hint_range(0.0, 0.1) = 0.023;

void fragment() {
	float r = corner_radius;

	// Gap between each card edge and the inscribed rectangle's edge.
	// r * (1 - 1/sqrt(2)) ≈ r * 0.29289
	float gap_u = r * 0.29289 / card_size.x;
	float gap_v = r * 0.29289 / card_size.y;

	// Mirror outward into each edge gap band independently.
	vec2 uv = UV;
	if      (uv.x < gap_u)            uv.x = 2.0 * gap_u - uv.x;
	else if (uv.x > 1.0 - gap_u)      uv.x = 2.0 * (1.0 - gap_u) - uv.x;
	if      (uv.y < gap_v)            uv.y = 2.0 * gap_v - uv.y;
	else if (uv.y > 1.0 - gap_v)      uv.y = 2.0 * (1.0 - gap_v) - uv.y;

	COLOR = texture(TEXTURE, uv);

	// Rounded-rectangle SDF clip (identical math to the spatial shader).
	vec2 p = (UV - 0.5) * card_size;
	vec2 q = abs(p) - (card_size * 0.5 - r);
	float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
	COLOR.a *= (sdf < 0.0 ? 1.0 : 0.0);
}

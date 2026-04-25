// Canvas-item shader for the popup card art TextureRect.
// Clips the texture to a rounded rectangle whose corner radius matches the
// proportional radius used by card_face_rounded.gdshader on the 3D card face.
shader_type canvas_item;

// Pixel dimensions of the card art rect (must match CARD_ART_W × CARD_ART_H
// in card_zoom_popup.gd).
uniform vec2 card_size = vec2(322.0, 449.0);
// Corner radius in pixels.  Derived from the 3D shader's 0.023 world-unit
// radius on a 0.63-wide card: 0.023/0.63 × 322 ≈ 11.7.
uniform float corner_radius : hint_range(0.0, 50.0) = 11.7;

void fragment() {
	vec2 pix = UV * card_size;
	vec2 q   = abs(pix - card_size * 0.5) - (card_size * 0.5 - corner_radius);
	float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - corner_radius;
	COLOR   = texture(TEXTURE, UV);
	COLOR.a *= sdf < 0.0 ? 1.0 : 0.0;
}

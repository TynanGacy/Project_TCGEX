class_name CardFace
extends Control
## Renders the card's face into a SubViewport.
##
## Hand mode (setup):       full card image stretched to fill 252×352.
## Board mode (setup_board): just the painted art cropped from the card image,
##                           rendered at landscape aspect ratio into 252×166.
##
## Board-mode info (name, HP, type) is displayed on a separate 3D nameplate
## attached to the Card node — not overlaid on this viewport.

## Full card image dimensions (hand mode).
const FACE_SIZE := Vector2(252, 352)

## Board mode: painted-art crop.
## Calibrated to RS set scans (400 × 550 px).
## The art window spans roughly x 8–92 %, y 15–55 % of the full card image.
const BOARD_ART_UV    := Rect2(0.08, 0.08, 0.84, 0.401)
## Resulting art aspect ratio (width : height ≈ 336 × 221 px → 1.52 : 1).
const BOARD_ART_RATIO := 1.52
## Viewport size for board mode (252 wide, height = 252 / 1.52).
const BOARD_FACE_SIZE := Vector2(252, 166)

const TYPE_COLORS: Array[Color] = [
	Color(0.70, 0.70, 0.70),  # NONE
	Color(0.95, 0.40, 0.10),  # FIRE
	Color(0.20, 0.50, 0.95),  # WATER
	Color(0.20, 0.75, 0.20),  # GRASS
	Color(0.95, 0.85, 0.10),  # LIGHTNING
	Color(0.70, 0.20, 0.90),  # PSYCHIC
	Color(0.75, 0.35, 0.10),  # FIGHTING
	Color(0.15, 0.08, 0.28),  # DARKNESS
	Color(0.55, 0.60, 0.65),  # METAL
	Color(0.10, 0.55, 0.50),  # DRAGON
	Color(0.85, 0.82, 0.75),  # COLORLESS
]

const TRAINER_KIND_COLORS: Array[Color] = [
	Color(0.20, 0.50, 0.85),  # ITEM
	Color(0.85, 0.40, 0.10),  # SUPPORTER
	Color(0.15, 0.60, 0.30),  # STADIUM
	Color(0.50, 0.20, 0.70),  # TOOL
]

const CARD_BG := Color(0.97, 0.95, 0.90)
const TRAINER_KIND_NAMES: Array[String] = ["Item", "Supporter", "Stadium", "Tool"]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Hand mode: display the full card image, portrait, no crops.
func setup(data: CardData) -> void:
	_clear_to(FACE_SIZE)
	if data.art != null:
		var tex := TextureRect.new()
		tex.texture = data.art
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.position = Vector2.ZERO
		tex.size = FACE_SIZE
		add_child(tex)
	else:
		_add_rect(Vector2.ZERO, FACE_SIZE, _fallback_color(data))
		var lbl := _add_label(data.display_name, 28, Color.WHITE,
			Vector2(8.0, FACE_SIZE.y / 2.0 - 20.0))
		lbl.size.x = FACE_SIZE.x - 16.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Board mode: display only the painted art cropped from the card image.
## Viewport is resized to BOARD_FACE_SIZE (landscape); the Card node's face
## mesh is expected to match these proportions.
func setup_board(data: CardData) -> void:
	_clear_to(BOARD_FACE_SIZE)
	if data == null:
		return
	if data.art != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = data.art
		atlas.region = Rect2(
			data.art.get_width()  * BOARD_ART_UV.position.x,
			data.art.get_height() * BOARD_ART_UV.position.y,
			data.art.get_width()  * BOARD_ART_UV.size.x,
			data.art.get_height() * BOARD_ART_UV.size.y
		)
		var tex := TextureRect.new()
		tex.texture = atlas
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.position = Vector2.ZERO
		tex.size = BOARD_FACE_SIZE
		add_child(tex)
	else:
		_add_rect(Vector2.ZERO, BOARD_FACE_SIZE, _fallback_color(data))
		var lbl := _add_label(data.display_name, 22, Color.WHITE,
			Vector2(8.0, BOARD_FACE_SIZE.y / 2.0 - 14.0))
		lbl.size.x = BOARD_FACE_SIZE.x - 16.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _clear_to(target_size: Vector2) -> void:
	for child in get_children():
		child.queue_free()
	custom_minimum_size = target_size
	size = target_size
	if get_parent() is SubViewport:
		get_parent().size = Vector2i(target_size)


func _fallback_color(data: CardData) -> Color:
	if data is PokemonCardData:
		return _type_color((data as PokemonCardData).pokemon_type)
	if data is EnergyCardData:
		return _type_color((data as EnergyCardData).energy_type)
	if data is TrainerCardData:
		var kind: int = (data as TrainerCardData).trainer_kind
		return TRAINER_KIND_COLORS[kind]
	return CARD_BG


func _type_color(t: PokemonCardData.EnergyType) -> Color:
	var idx := int(t)
	if idx >= 0 and idx < TYPE_COLORS.size():
		return TYPE_COLORS[idx]
	return Color(0.85, 0.82, 0.75)


func _add_rect(pos: Vector2, sz: Vector2, col: Color) -> ColorRect:
	var cr := ColorRect.new()
	cr.position = pos
	cr.size = sz
	cr.color = col
	add_child(cr)
	return cr


func _add_label(text: String, font_size: int, col: Color, pos: Vector2) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", col)
	lbl.position = pos
	add_child(lbl)
	return lbl

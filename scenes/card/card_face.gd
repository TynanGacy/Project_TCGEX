class_name CardFace
extends Control
## Renders the card's face into a SubViewport.
## Displays data.art stretched to fill the full face, preserving whatever
## aspect ratio the source texture has (typically the full card scan).
## Falls back to a type-colour background + card name if no art is loaded.
##
## Board-mode info (name, HP, type) is shown on a separate 3D nameplate
## attached to the card node rather than overlaid on this viewport.

const FACE_SIZE := Vector2(252, 352)

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


func setup(data: CardData) -> void:
	_build(data)


## Alias kept for call-site clarity; rendering is identical for both modes.
## Board-mode info display is handled by the Card node's nameplate object.
func setup_board(inst: CardInstance) -> void:
	_build(inst.data)


func _build(data: CardData) -> void:
	for child in get_children():
		child.queue_free()
	custom_minimum_size = FACE_SIZE
	size = FACE_SIZE
	if get_parent() is SubViewport:
		get_parent().size = Vector2i(FACE_SIZE)

	if data.art != null:
		## Stretch the full card-scan image to fill the face exactly.
		## STRETCH_SCALE fills without cropping; works cleanly when the source
		## texture already matches the card's portrait aspect ratio.
		var tex := TextureRect.new()
		tex.texture = data.art
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.position = Vector2.ZERO
		tex.size = FACE_SIZE
		add_child(tex)
	else:
		## Fallback: solid type colour + centred name.
		_add_rect(Vector2.ZERO, FACE_SIZE, _fallback_color(data))
		var lbl := _add_label(data.display_name, 28, Color.WHITE,
			Vector2(8.0, FACE_SIZE.y / 2.0 - 20.0))
		lbl.size.x = FACE_SIZE.x - 16.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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

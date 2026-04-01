class_name CardFace
extends Control
## Renders a card's face as a 2D layout inside a SubViewport.
## Call setup(data) to populate; the parent SubViewport should then trigger
## render_target_update_mode = UPDATE_ONCE to capture the frame.

const FACE_SIZE := Vector2(252, 352)

## Energy type → background colour (index matches PokemonCardData.EnergyType).
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
const STAGE_NAMES: Array[String] = ["Basic", "Stage 1", "Stage 2"]
const TRAINER_KIND_NAMES: Array[String] = ["Item", "Supporter", "Stadium", "Tool"]


func setup(data: CardData) -> void:
	for child in get_children():
		child.queue_free()
	custom_minimum_size = FACE_SIZE
	size = FACE_SIZE

	if data is PokemonCardData:
		_build_pokemon_face(data as PokemonCardData)
	elif data is EnergyCardData:
		_build_energy_face(data as EnergyCardData)
	elif data is TrainerCardData:
		_build_trainer_face(data as TrainerCardData)
	else:
		_build_generic_face(data)


# ---------------------------------------------------------------------------
# Pokemon
# ---------------------------------------------------------------------------

func _build_pokemon_face(data: PokemonCardData) -> void:
	var type_color := _type_color(data.pokemon_type)

	# Full background
	_add_rect(Vector2.ZERO, FACE_SIZE, CARD_BG)

	# Coloured header band
	_add_rect(Vector2.ZERO, Vector2(FACE_SIZE.x, 64), type_color)

	# Stage badge
	var stage_lbl := _add_label(
		STAGE_NAMES[data.stage], 15, Color.WHITE, Vector2(8, 6))
	stage_lbl.size.x = 100

	# Name
	var name_lbl := _add_label(data.display_name, 22, Color.WHITE, Vector2(8, 28))
	name_lbl.size.x = FACE_SIZE.x - 80

	# HP (top-right)
	var hp_lbl := _add_label("%d HP" % data.hp_max, 20, Color.WHITE,
		Vector2(FACE_SIZE.x - 72, 28))
	hp_lbl.size.x = 68
	hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Art placeholder or real texture
	if data.art:
		var tex_rect := TextureRect.new()
		tex_rect.texture = data.art
		tex_rect.position = Vector2(12, 68)
		tex_rect.size = Vector2(228, 150)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(tex_rect)
	else:
		_add_rect(Vector2(12, 68), Vector2(228, 150), type_color.darkened(0.35))
		var type_lbl := _add_label(
			PokemonCardData.energy_type_to_string(data.pokemon_type),
			26, Color.WHITE, Vector2(12, 148))
		type_lbl.size.x = 228
		type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Divider line
	_add_rect(Vector2(8, 226), Vector2(FACE_SIZE.x - 16, 2),
		type_color.darkened(0.2))

	# Attacks
	var atk_y := 234.0
	for attack in data.attacks.slice(0, 2):
		var atk_lbl := _add_label(
			"%s  %d" % [attack.name, attack.base_damage],
			16, Color(0.15, 0.15, 0.15), Vector2(12, atk_y))
		atk_lbl.size.x = FACE_SIZE.x - 24
		atk_y += 30.0

	# Bottom info bar
	_add_rect(Vector2(0, FACE_SIZE.y - 34), Vector2(FACE_SIZE.x, 34),
		type_color.darkened(0.15))
	var retreat_lbl := _add_label(
		"Retreat: %d" % data.retreat_cost,
		13, Color.WHITE, Vector2(8, FACE_SIZE.y - 26))
	retreat_lbl.size.x = FACE_SIZE.x / 2.0


# ---------------------------------------------------------------------------
# Energy
# ---------------------------------------------------------------------------

func _build_energy_face(data: EnergyCardData) -> void:
	var tc := _type_color(data.energy_type)

	_add_rect(Vector2.ZERO, FACE_SIZE, tc)
	# Subtle dark vignette overlay
	_add_rect(Vector2.ZERO, FACE_SIZE, Color(0.0, 0.0, 0.0, 0.12))

	var header_lbl := _add_label("ENERGY", 20, Color.WHITE, Vector2(0, 16))
	header_lbl.size.x = FACE_SIZE.x
	header_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Big circle placeholder for energy symbol
	_add_rect(Vector2(76, 60), Vector2(100, 100), tc.lightened(0.3))

	var name_lbl := _add_label(data.display_name, 26, Color.WHITE,
		Vector2(0, 180))
	name_lbl.size.x = FACE_SIZE.x
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var type_lbl := _add_label(
		PokemonCardData.energy_type_to_string(data.energy_type),
		34, Color.WHITE, Vector2(0, 214))
	type_lbl.size.x = FACE_SIZE.x
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var prov_lbl := _add_label("Provides: %d" % data.provides,
		18, Color(1, 1, 1, 0.85), Vector2(0, 290))
	prov_lbl.size.x = FACE_SIZE.x
	prov_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


# ---------------------------------------------------------------------------
# Trainer
# ---------------------------------------------------------------------------

func _build_trainer_face(data: TrainerCardData) -> void:
	var kind: int = data.trainer_kind
	var kc := TRAINER_KIND_COLORS[kind]

	_add_rect(Vector2.ZERO, FACE_SIZE, CARD_BG)
	_add_rect(Vector2.ZERO, Vector2(FACE_SIZE.x, 84), kc)

	var sub_lbl := _add_label(
		"Trainer — " + TRAINER_KIND_NAMES[kind], 15, Color.WHITE, Vector2(8, 8))
	sub_lbl.size.x = FACE_SIZE.x - 16

	var name_lbl := _add_label(data.display_name, 26, Color.WHITE, Vector2(8, 36))
	name_lbl.size.x = FACE_SIZE.x - 16

	# Art placeholder or real texture
	if data.art:
		var tex_rect := TextureRect.new()
		tex_rect.texture = data.art
		tex_rect.position = Vector2(12, 90)
		tex_rect.size = Vector2(228, 148)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(tex_rect)
	else:
		_add_rect(Vector2(12, 90), Vector2(228, 148), kc.darkened(0.4))

	# Rules text box
	_add_rect(Vector2(8, 246), Vector2(FACE_SIZE.x - 16, 2),
		kc.darkened(0.2))
	if data.rules_text != "":
		var rules_lbl := _add_label(
			data.rules_text, 14, Color(0.18, 0.18, 0.18), Vector2(12, 252))
		rules_lbl.size = Vector2(FACE_SIZE.x - 24, 88)
		rules_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD

	# Kind stamp bottom-right
	var stamp_lbl := _add_label(TRAINER_KIND_NAMES[kind].to_upper(),
		12, kc.darkened(0.3), Vector2(0, FACE_SIZE.y - 22))
	stamp_lbl.size.x = FACE_SIZE.x - 8
	stamp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


# ---------------------------------------------------------------------------
# Generic fallback
# ---------------------------------------------------------------------------

func _build_generic_face(data: CardData) -> void:
	_add_rect(Vector2.ZERO, FACE_SIZE, CARD_BG)
	var lbl := _add_label(data.display_name, 24, Color(0.1, 0.1, 0.1),
		Vector2(0, FACE_SIZE.y / 2.0 - 16))
	lbl.size.x = FACE_SIZE.x
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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


func _add_label(text: String, font_size: int, col: Color,
		pos: Vector2) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", col)
	lbl.position = pos
	add_child(lbl)
	return lbl

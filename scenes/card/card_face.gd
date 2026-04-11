class_name CardFace
extends Control
## Renders a card's face as a 2D layout inside a SubViewport.
## Call setup(data)       for hand mode  (static card data, full-face layout).
## Call setup_board(inst) for board mode (live HP, compact header + correct art ratio).
## The parent SubViewport should trigger render_target_update_mode = UPDATE_ONCE after each call.

const FACE_SIZE := Vector2(252, 352)

## Hand mode art area bounds.
const ART_TOP    := 56.0
const ART_BOTTOM := 308.0

## Board mode layout.
## Pokemon TCG card art is approximately 1.436 : 1 (width : height).
## For 252 px wide: art height = 252 / 1.436 ≈ 176 px.
const BOARD_HDR_H    := 56.0
const BOARD_ART_H    := 176.0
const BOARD_ART_RATIO := 1.436

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
const TRAINER_KIND_NAMES: Array[String] = ["Item", "Supporter", "Stadium", "Tool"]

var _board_mode: bool = false
var _board_inst: CardInstance = null


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func setup(data: CardData) -> void:
	_board_mode = false
	_board_inst = null
	_clear_children()
	if data is PokemonCardData:
		_build_pokemon_face(data as PokemonCardData)
	elif data is EnergyCardData:
		_build_energy_face(data as EnergyCardData)
	elif data is TrainerCardData:
		_build_trainer_face(data as TrainerCardData)
	else:
		_build_generic_face(data)


func setup_board(inst: CardInstance) -> void:
	_board_mode = true
	_board_inst = inst
	_clear_children()
	if inst.data is PokemonCardData:
		_build_board_pokemon_face(inst)
	elif inst.data is EnergyCardData:
		_build_board_energy_face(inst)
	elif inst.data is TrainerCardData:
		_build_board_trainer_face(inst)
	else:
		_build_board_generic_face(inst)


func _clear_children() -> void:
	for child in get_children():
		child.queue_free()
	custom_minimum_size = FACE_SIZE
	size = FACE_SIZE
	if get_parent() is SubViewport:
		get_parent().size = Vector2i(FACE_SIZE)


# ---------------------------------------------------------------------------
# Hand mode (static CardData)
# ---------------------------------------------------------------------------

func _build_pokemon_face(data: PokemonCardData) -> void:
	var tc := _type_color(data.pokemon_type)
	_add_rect(Vector2.ZERO, FACE_SIZE, tc)
	_add_art_or_placeholder(data.art, tc, PokemonCardData.energy_type_to_string(data.pokemon_type))
	_add_header_bar(data.display_name, "%d HP" % data.hp_max)


func _build_energy_face(data: EnergyCardData) -> void:
	var tc := _type_color(data.energy_type)
	_add_rect(Vector2.ZERO, FACE_SIZE, tc)
	_add_art_or_placeholder(data.art, tc.darkened(0.25), PokemonCardData.energy_type_to_string(data.energy_type))
	_add_header_bar("Energy", PokemonCardData.energy_type_to_string(data.energy_type))


func _build_trainer_face(data: TrainerCardData) -> void:
	var kind: int = data.trainer_kind
	var kc := TRAINER_KIND_COLORS[kind]
	_add_rect(Vector2.ZERO, FACE_SIZE, kc)
	_add_art_or_placeholder(data.art, kc.darkened(0.35), TRAINER_KIND_NAMES[kind])
	_add_header_bar(data.display_name, TRAINER_KIND_NAMES[kind])


func _build_generic_face(data: CardData) -> void:
	_add_rect(Vector2.ZERO, FACE_SIZE, CARD_BG)
	var lbl := _add_label(data.display_name, 24, Color(0.1, 0.1, 0.1),
		Vector2(0, FACE_SIZE.y / 2.0 - 16))
	lbl.size.x = FACE_SIZE.x
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


# ---------------------------------------------------------------------------
# Board mode (live CardInstance)
# ---------------------------------------------------------------------------

func _build_board_pokemon_face(inst: CardInstance) -> void:
	var data := inst.data as PokemonCardData
	var tc := _type_color(data.pokemon_type)
	var type_str := PokemonCardData.energy_type_to_string(data.pokemon_type)
	_add_rect(Vector2.ZERO, FACE_SIZE, tc)
	_add_board_art_or_placeholder(data.art, tc.darkened(0.25), type_str)
	_add_board_header(data.display_name, inst.hp_remaining(), inst.hp_max(), type_str)


func _build_board_energy_face(inst: CardInstance) -> void:
	var data := inst.data as EnergyCardData
	var tc := _type_color(data.energy_type)
	var type_str := PokemonCardData.energy_type_to_string(data.energy_type)
	_add_rect(Vector2.ZERO, FACE_SIZE, tc)
	_add_board_art_or_placeholder(data.art, tc.darkened(0.25), type_str)
	_add_board_header("Energy", 0, 0, type_str)


func _build_board_trainer_face(inst: CardInstance) -> void:
	var data := inst.data as TrainerCardData
	var kind: int = data.trainer_kind
	var kc := TRAINER_KIND_COLORS[kind]
	_add_rect(Vector2.ZERO, FACE_SIZE, kc)
	_add_board_art_or_placeholder(data.art, kc.darkened(0.35), TRAINER_KIND_NAMES[kind])
	_add_board_header(data.display_name, 0, 0, TRAINER_KIND_NAMES[kind])


func _build_board_generic_face(inst: CardInstance) -> void:
	_add_rect(Vector2.ZERO, FACE_SIZE, CARD_BG)
	var lbl := _add_label(inst.data.display_name, 24, Color(0.1, 0.1, 0.1),
		Vector2(0, FACE_SIZE.y / 2.0 - 16))
	lbl.size.x = FACE_SIZE.x
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


# ---------------------------------------------------------------------------
# Shared layout helpers
# ---------------------------------------------------------------------------

## Hand mode: semi-transparent dark bar at the top with name (left) and label (right).
func _add_header_bar(left_text: String, right_text: String) -> void:
	_add_rect(Vector2.ZERO, Vector2(FACE_SIZE.x, ART_TOP), Color(0.0, 0.0, 0.0, 0.50))
	var name_lbl := _add_label(left_text, 24, Color.WHITE, Vector2(8, 10))
	name_lbl.size.x = FACE_SIZE.x - 84
	var right_lbl := _add_label(right_text, 18, Color(1.0, 1.0, 1.0, 0.90), Vector2(FACE_SIZE.x - 80, 14))
	right_lbl.size.x = 72
	right_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


## Board mode: compact header showing name, energy type, and live HP fraction.
func _add_board_header(name: String, hp_rem: int, hp_max_val: int, type_str: String) -> void:
	_add_rect(Vector2.ZERO, Vector2(FACE_SIZE.x, BOARD_HDR_H), Color(0.0, 0.0, 0.0, 0.65))
	## Name — top-left.
	var name_lbl := _add_label(name, 20, Color.WHITE, Vector2(6, 4))
	name_lbl.size.x = 152
	## Type — below name.
	var type_lbl := _add_label(type_str, 14, Color(1.0, 1.0, 0.85, 0.85), Vector2(6, 30))
	type_lbl.size.x = 152
	## HP fraction — right side.  Hidden for non-Pokemon cards (hp_max_val == 0).
	if hp_max_val > 0:
		var hp_lbl := _add_label("%d/%d\nHP" % [hp_rem, hp_max_val], 18, Color.WHITE,
			Vector2(164, 4))
		hp_lbl.size.x = 82
		hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


## Hand mode: fills the art area (ART_TOP → ART_BOTTOM) with the card's art or a placeholder.
func _add_art_or_placeholder(art: Texture2D, placeholder_color: Color, type_label: String) -> void:
	var art_size := Vector2(FACE_SIZE.x, ART_BOTTOM - ART_TOP)

	if art != null:
		var clipper := Control.new()
		clipper.position = Vector2(0.0, ART_TOP)
		clipper.size = art_size
		clipper.clip_contents = true
		add_child(clipper)
		var tex_rect := TextureRect.new()
		tex_rect.texture = art
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_rect.position = Vector2.ZERO
		tex_rect.size = art_size
		clipper.add_child(tex_rect)
	else:
		_add_rect(Vector2(8.0, ART_TOP + 4.0), Vector2(FACE_SIZE.x - 16.0, art_size.y - 8.0), placeholder_color)
		var lbl := _add_label(type_label, 52, Color(1.0, 1.0, 1.0, 0.35),
			Vector2(0.0, ART_TOP + art_size.y / 2.0 - 36.0))
		lbl.size.x = FACE_SIZE.x
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Board mode: fills the art area below the header at the correct TCG art aspect ratio.
func _add_board_art_or_placeholder(art: Texture2D, placeholder_color: Color, type_label: String) -> void:
	var art_size := Vector2(FACE_SIZE.x, BOARD_ART_H)

	if art != null:
		var clipper := Control.new()
		clipper.position = Vector2(0.0, BOARD_HDR_H)
		clipper.size = art_size
		clipper.clip_contents = true
		add_child(clipper)
		var tex_rect := TextureRect.new()
		tex_rect.texture = art
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_rect.position = Vector2.ZERO
		tex_rect.size = art_size
		clipper.add_child(tex_rect)
	else:
		_add_rect(
			Vector2(8.0, BOARD_HDR_H + 4.0),
			Vector2(FACE_SIZE.x - 16.0, BOARD_ART_H - 8.0),
			placeholder_color
		)
		var lbl := _add_label(type_label, 42, Color(1.0, 1.0, 1.0, 0.35),
			Vector2(0.0, BOARD_HDR_H + BOARD_ART_H / 2.0 - 28.0))
		lbl.size.x = FACE_SIZE.x
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


# ---------------------------------------------------------------------------
# Primitive helpers
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


func _add_label(text: String, font_size: int, col: Color, pos: Vector2) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", col)
	lbl.position = pos
	add_child(lbl)
	return lbl

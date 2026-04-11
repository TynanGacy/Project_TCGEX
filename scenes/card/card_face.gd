class_name CardFace
extends Control
## Renders a card's face as a 2D layout inside a SubViewport.
## Call setup(data) to populate; the parent SubViewport should then trigger
## render_target_update_mode = UPDATE_ONCE to capture the frame.
##
## Board layout: name + HP header bar, art (or type-color placeholder) body.
## Full card details are available in the zoom popup.

const FACE_SIZE := Vector2(252, 352)

const ART_TOP    := 56.0   ## y where the art area begins
const ART_BOTTOM := 308.0  ## y where the art area ends (~square at 252×252)

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


func setup(data: CardData) -> void:
	for child in get_children():
		child.queue_free()
	custom_minimum_size = FACE_SIZE
	size = FACE_SIZE
	if get_parent() is SubViewport:
		get_parent().size = Vector2i(FACE_SIZE)
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
	var tc := _type_color(data.pokemon_type)
	## Background.
	_add_rect(Vector2.ZERO, FACE_SIZE, tc)
	## Art area.
	_add_art_or_placeholder(data.art, tc, PokemonCardData.energy_type_to_string(data.pokemon_type))
	## Header bar overlay on top of art.
	_add_header_bar(data.display_name, "%d HP" % data.hp_max)


# ---------------------------------------------------------------------------
# Energy
# ---------------------------------------------------------------------------

func _build_energy_face(data: EnergyCardData) -> void:
	var tc := _type_color(data.energy_type)
	_add_rect(Vector2.ZERO, FACE_SIZE, tc)
	_add_art_or_placeholder(data.art, tc.darkened(0.25), PokemonCardData.energy_type_to_string(data.energy_type))
	_add_header_bar("Energy", PokemonCardData.energy_type_to_string(data.energy_type))


# ---------------------------------------------------------------------------
# Trainer
# ---------------------------------------------------------------------------

func _build_trainer_face(data: TrainerCardData) -> void:
	var kind: int = data.trainer_kind
	var kc := TRAINER_KIND_COLORS[kind]
	_add_rect(Vector2.ZERO, FACE_SIZE, kc)
	_add_art_or_placeholder(data.art, kc.darkened(0.35), TRAINER_KIND_NAMES[kind])
	_add_header_bar(data.display_name, TRAINER_KIND_NAMES[kind])


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
# Shared layout helpers
# ---------------------------------------------------------------------------

## Draws a semi-transparent dark bar at the top with a left label and a
## right label (e.g. name + HP, or name + type).
func _add_header_bar(left_text: String, right_text: String) -> void:
	_add_rect(Vector2.ZERO, Vector2(FACE_SIZE.x, ART_TOP), Color(0.0, 0.0, 0.0, 0.50))
	var name_lbl := _add_label(left_text, 24, Color.WHITE, Vector2(8, 10))
	name_lbl.size.x = FACE_SIZE.x - 84
	var right_lbl := _add_label(right_text, 18, Color(1.0, 1.0, 1.0, 0.90), Vector2(FACE_SIZE.x - 80, 14))
	right_lbl.size.x = 72
	right_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


## Fills the art area (ART_TOP → ART_BOTTOM) with either the card's art
## texture or a solid-colour placeholder with a faint type label.
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

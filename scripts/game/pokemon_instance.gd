class_name PokemonInstance
extends Node3D
## An in-play Pokemon. Owns all dynamic per-Pokemon state AND the visual
## representation of that state.
##
## PokemonInstance is responsible for:
##   - Storing Max/Current HP, special conditions, attached energy/tools,
##     previous evolutions, and any dynamic modifiers.
##   - Storing every card currently contained in this instance (the base
##     Pokemon, any prior evolution stages, attached energy, attached tools).
##   - Rendering its own visual (3D card face + HP label + attachment icons
##     + status badges).
##   - Updating that visual whenever its state changes — it does NOT consult
##     game rules or ask permission; the Manager is responsible for legality.
##
## When the Pokemon is knocked out or otherwise removed, call release_cards()
## to collect every card contained and discard the instance.

enum SpecialCondition { ASLEEP, BURNED, CONFUSED, PARALYZED, POISONED }

## --- Static state -----------------------------------------------------------
var card: PokemonCardData = null     ## Top (current) card of the evolution stack.
var prior_stages: Array[PokemonCardData] = []  ## Underneath, oldest first.
var owner_id: int = 0

## --- Dynamic state ----------------------------------------------------------
var max_hp: int = 0
var current_hp: int = 0
var special_conditions: Array[SpecialCondition] = []
var attached_energy: Array[CardData] = []
var attached_tools: Array[CardData] = []

## Dynamic modifiers applied by board effects.  Keyed by modifier id (String),
## value is an arbitrary Dictionary the effect defines.  Cleared on release.
var modifiers: Dictionary = {}

## --- Visual -----------------------------------------------------------------
const _CARD_SCENE := preload("res://scenes/card/card.tscn")

## Nameplate (name / HP / type symbol) layout.  Heights and offsets are
## fractions of the landscape board-mode card height so the strip scales
## with active vs bench cards.
const NAMEPLATE_H_RATIO   := 0.18   ## strip height, as a fraction of card height
const NAMEPLATE_Y_LIFT    := 0.014  ## world-space lift above the card surface
const NAMEPLATE_BG_COLOR  := Color(0.05, 0.05, 0.05, 0.90)

## Group B (Sleep / Paralyzed / Confused) — translucent halo around the card.
const HALO_MARGIN := 0.030  ## extra world units on each side beyond card edge
const HALO_Y_LIFT := 0.007  ## just above the card top face
const HALO_ALPHA  := 0.38
## Group A (Poison / Burn) — coloured badge discs.
const PSN_BADGE_COLOR := Color(0.55, 0.18, 0.82)  ## purple
const BRN_BADGE_COLOR := Color(0.95, 0.32, 0.08)  ## orange-red
const TYPE_SYMBOL_COLORS: Array[Color] = [
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

## Width (world units) used by the card face in board mode.  Set by whoever
## places the instance (typically a DropZone via BoardPosition).
var display_width: float = 1.32

var _card_visual: Card = null
var _nameplate_node: Node3D = null
var _nameplate_bg: MeshInstance3D = null
var _name_label: Label3D = null
var _hp_label: Label3D = null
var _type_symbol_mesh: MeshInstance3D = null
var _type_symbol_mat: StandardMaterial3D = null
var _condition_label: Label3D = null
## Group B halo — a translucent plane slightly larger than the card.
var _status_halo_mesh: MeshInstance3D = null
var _status_halo_mat: StandardMaterial3D = null
## Group A badge discs — one each for Poison and Burn.
var _psn_badge_disc: MeshInstance3D = null
var _psn_badge_label: Label3D = null
var _brn_badge_disc: MeshInstance3D = null
var _brn_badge_label: Label3D = null

## Attachment icon pool — built once, updated on every refresh_visual().
var _attachment_node: Node3D = null
var _energy_icon_discs: Array[MeshInstance3D] = []
var _energy_icon_labels: Array[Label3D] = []
var _energy_overflow_disc: MeshInstance3D = null
var _energy_overflow_label: Label3D = null
var _tool_icon_disc: MeshInstance3D = null
var _tool_icon_label: Label3D = null


static func create(pokemon_card: PokemonCardData, owner: int = 0) -> PokemonInstance:
	var inst := PokemonInstance.new()
	inst.card = pokemon_card
	inst.owner_id = owner
	inst.max_hp = pokemon_card.hp_max if pokemon_card != null else 0
	inst.current_hp = inst.max_hp
	return inst


func _ready() -> void:
	_build_visual()
	refresh_visual()


func _build_visual() -> void:
	_card_visual = _CARD_SCENE.instantiate() as Card
	add_child(_card_visual)  ## add_child first so @onready nodes are live
	_card_visual.set_display_width(display_width)
	_card_visual.set_board_mode(true)
	_card_visual.set_data(card)

	_build_nameplate()
	_build_attachments()
	_build_status_halo()
	_build_condition_badges()

	_condition_label = Label3D.new()
	_condition_label.name = "ConditionLabel"
	_condition_label.pixel_size = 0.0009
	_condition_label.font_size = 28
	_condition_label.modulate = Color(1.0, 0.7, 0.4)
	_condition_label.outline_size = 6
	_condition_label.outline_modulate = Color.BLACK
	_condition_label.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	_condition_label.position = Vector3(display_width * 0.30, 0.03, display_width * 0.18)
	add_child(_condition_label)


## --- Group B halo (Sleep / Paralyzed / Confused) ----------------------------

func _build_status_halo() -> void:
	_status_halo_mesh = MeshInstance3D.new()
	_status_halo_mesh.name = "StatusHalo"
	_status_halo_mesh.mesh = PlaneMesh.new()
	_status_halo_mat = StandardMaterial3D.new()
	_status_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_status_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_status_halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_status_halo_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	_status_halo_mesh.set_surface_override_material(0, _status_halo_mat)
	_status_halo_mesh.visible = false
	add_child(_status_halo_mesh)
	_layout_status_halo()


func _layout_status_halo() -> void:
	if _status_halo_mesh == null:
		return
	var card_w: float = display_width
	var card_h: float = display_width / Card.BOARD_ART_RATIO
	(_status_halo_mesh.mesh as PlaneMesh).size = Vector2(
		card_w + HALO_MARGIN * 2.0,
		card_h + HALO_MARGIN * 2.0
	)
	_status_halo_mesh.position = Vector3(0.0, HALO_Y_LIFT, 0.0)


## --- Group A badges (Poison / Burn) -----------------------------------------

func _build_condition_badges() -> void:
	_psn_badge_disc = _make_disc_mesh(PSN_BADGE_COLOR)
	_psn_badge_disc.name = "PsnBadgeDisc"
	add_child(_psn_badge_disc)
	_psn_badge_label = _make_condition_badge_label("PSN")
	add_child(_psn_badge_label)

	_brn_badge_disc = _make_disc_mesh(BRN_BADGE_COLOR)
	_brn_badge_disc.name = "BrnBadgeDisc"
	add_child(_brn_badge_disc)
	_brn_badge_label = _make_condition_badge_label("BRN")
	add_child(_brn_badge_label)

	_psn_badge_disc.visible = false
	_psn_badge_label.visible = false
	_brn_badge_disc.visible = false
	_brn_badge_label.visible = false
	_layout_condition_badges()


func _layout_condition_badges() -> void:
	var card_w: float = display_width
	var card_h: float = display_width / Card.BOARD_ART_RATIO
	var badge_r: float = card_h * 0.09
	var badge_y: float = 0.015
	var label_y: float = 0.027
	## Right side of card, upper half — below the nameplate strip.
	var bx: float = card_w * 0.32
	var psn_z: float = -card_h * 0.22
	var brn_z: float = psn_z + badge_r * 2.6

	for pair in [
		[_psn_badge_disc, _psn_badge_label, psn_z],
		[_brn_badge_disc, _brn_badge_label, brn_z],
	]:
		var disc: MeshInstance3D = pair[0]
		var lbl: Label3D = pair[1]
		var bz: float = pair[2]
		if disc == null:
			continue
		var cyl := disc.mesh as CylinderMesh
		cyl.top_radius = badge_r
		cyl.bottom_radius = badge_r
		disc.position = Vector3(bx, badge_y, bz)
		if lbl != null:
			lbl.position = Vector3(bx, label_y, bz)


## --- Condition visual refresh ------------------------------------------------

func _refresh_condition_visuals() -> void:
	## Group B: only one of Sleep / Paralyzed / Confused can be active at once.
	var group_b: int = -1
	for c in special_conditions:
		if c == SpecialCondition.ASLEEP or c == SpecialCondition.PARALYZED \
				or c == SpecialCondition.CONFUSED:
			group_b = c
			break
	if _status_halo_mesh != null and _status_halo_mat != null:
		if group_b == -1:
			_status_halo_mesh.visible = false
		else:
			_status_halo_mat.albedo_color = _group_b_halo_color(group_b)
			_status_halo_mesh.visible = true

	## Group A: Poison and Burn are independent.
	var has_psn: bool = special_conditions.has(SpecialCondition.POISONED)
	var has_brn: bool = special_conditions.has(SpecialCondition.BURNED)
	if _psn_badge_disc != null:
		_psn_badge_disc.visible = has_psn
	if _psn_badge_label != null:
		_psn_badge_label.visible = has_psn
	if _brn_badge_disc != null:
		_brn_badge_disc.visible = has_brn
	if _brn_badge_label != null:
		_brn_badge_label.visible = has_brn


static func _group_b_halo_color(c: int) -> Color:
	match c:
		SpecialCondition.ASLEEP:    return Color(0.35, 0.40, 0.95, HALO_ALPHA)
		SpecialCondition.PARALYZED: return Color(0.95, 0.85, 0.10, HALO_ALPHA)
		SpecialCondition.CONFUSED:  return Color(0.90, 0.25, 0.80, HALO_ALPHA)
	return Color(0.0, 0.0, 0.0, 0.0)


static func _make_condition_badge_label(abbrev: String) -> Label3D:
	var lbl := Label3D.new()
	lbl.pixel_size = 0.0009
	lbl.font_size = 20
	lbl.modulate = Color.WHITE
	lbl.outline_size = 5
	lbl.outline_modulate = Color.BLACK
	lbl.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	lbl.text = abbrev
	return lbl


## Pushes current state to the visual.  Call after any mutation.
func refresh_visual() -> void:
	if _card_visual != null:
		_card_visual.set_data(card)
		_card_visual.face_down = false
	_refresh_nameplate()
	_refresh_attachments()
	if _condition_label != null:
		_condition_label.text = _conditions_text()
	_refresh_condition_visuals()


## --- Nameplate --------------------------------------------------------------

## Builds a flat 3D strip above the top edge of the landscape card showing
## the Pokemon's name (left), current/max HP (centre), and a type-colour
## symbol (right).  The type symbol is a placeholder coloured disc stamped
## with the type's first letter.
func _build_nameplate() -> void:
	_nameplate_node = Node3D.new()
	_nameplate_node.name = "Nameplate"

	_nameplate_bg = MeshInstance3D.new()
	_nameplate_bg.name = "NameplateBG"
	_nameplate_bg.mesh = PlaneMesh.new()
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = NAMEPLATE_BG_COLOR
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_nameplate_bg.set_surface_override_material(0, bg_mat)
	_nameplate_node.add_child(_nameplate_bg)

	_name_label = Label3D.new()
	_name_label.name = "NameLabel"
	_name_label.pixel_size = 0.0022
	_name_label.font_size = 48
	_name_label.modulate = Color.WHITE
	_name_label.outline_size = 8
	_name_label.outline_modulate = Color.BLACK
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_label.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	_nameplate_node.add_child(_name_label)

	_hp_label = Label3D.new()
	_hp_label.name = "HPLabel"
	_hp_label.pixel_size = 0.0022
	_hp_label.font_size = 42
	_hp_label.modulate = Color.WHITE
	_hp_label.outline_size = 8
	_hp_label.outline_modulate = Color.BLACK
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_label.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	_nameplate_node.add_child(_hp_label)

	_type_symbol_mesh = MeshInstance3D.new()
	_type_symbol_mesh.name = "TypeSymbol"
	var cyl := CylinderMesh.new()
	cyl.height = 0.004
	_type_symbol_mesh.mesh = cyl
	_type_symbol_mat = StandardMaterial3D.new()
	_type_symbol_mesh.set_surface_override_material(0, _type_symbol_mat)
	_nameplate_node.add_child(_type_symbol_mesh)

	add_child(_nameplate_node)
	_layout_nameplate()


func _layout_nameplate() -> void:
	if _nameplate_node == null:
		return
	var card_w: float = display_width
	var card_h: float = display_width / Card.BOARD_ART_RATIO
	var strip_h: float = card_h * NAMEPLATE_H_RATIO
	var half_w: float = card_w * 0.5

	(_nameplate_bg.mesh as PlaneMesh).size = Vector2(card_w, strip_h)

	## Position nameplate strip just past the top edge of the landscape card
	## (top edge is at local -card_h/2 on the Z axis).
	_nameplate_node.position = Vector3(0.0, NAMEPLATE_Y_LIFT, -(card_h * 0.5 + strip_h * 0.5))

	var lift := 0.002  ## tiny offset so labels sit above the bg plane
	var type_disc_radius: float = strip_h * 0.38
	var edge_pad: float = strip_h * 0.20
	var disc_x: float = half_w - edge_pad - type_disc_radius
	## HP label sits to the left of the disc, right-justified so it reads
	## "120/120 ●" with the coloured disc acting as the type symbol.
	var hp_x: float = disc_x - type_disc_radius - edge_pad * 0.5

	_name_label.position = Vector3(-half_w + edge_pad, lift, 0.0)
	_hp_label.position   = Vector3(hp_x, lift, 0.0)
	_type_symbol_mesh.position = Vector3(disc_x, lift, 0.0)

	var cyl := _type_symbol_mesh.mesh as CylinderMesh
	cyl.top_radius    = type_disc_radius
	cyl.bottom_radius = type_disc_radius


func _refresh_nameplate() -> void:
	if _nameplate_node == null:
		return
	_name_label.text = card.display_name if card != null else ""
	_hp_label.text   = "%d/%d" % [current_hp, max_hp]
	var type_idx: int = int(card.pokemon_type) if card != null else 0
	if type_idx < 0 or type_idx >= TYPE_SYMBOL_COLORS.size():
		type_idx = 0
	if _type_symbol_mat != null:
		_type_symbol_mat.albedo_color = TYPE_SYMBOL_COLORS[type_idx]


## --- Attachment display -----------------------------------------------------

func _build_attachments() -> void:
	_attachment_node = Node3D.new()
	_attachment_node.name = "Attachments"
	add_child(_attachment_node)

	for i in range(AttachmentDisplay.MAX_VISIBLE_ENERGY):
		var disc := _make_disc_mesh(Color.WHITE)
		disc.name = "EnergyDisc%d" % i
		var lbl := _make_icon_label()
		lbl.name = "EnergyLabel%d" % i
		_attachment_node.add_child(disc)
		_attachment_node.add_child(lbl)
		_energy_icon_discs.append(disc)
		_energy_icon_labels.append(lbl)
		disc.visible = false
		lbl.visible = false

	_energy_overflow_disc = _make_disc_mesh(Color(0.40, 0.40, 0.40))
	_energy_overflow_disc.name = "EnergyOverflowDisc"
	_attachment_node.add_child(_energy_overflow_disc)
	_energy_overflow_disc.visible = false

	_energy_overflow_label = Label3D.new()
	_energy_overflow_label.name = "EnergyOverflowLabel"
	_energy_overflow_label.pixel_size = 0.0009
	_energy_overflow_label.font_size = 22
	_energy_overflow_label.modulate = Color.WHITE
	_energy_overflow_label.outline_size = 5
	_energy_overflow_label.outline_modulate = Color.BLACK
	_energy_overflow_label.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	_energy_overflow_label.text = "+"
	_energy_overflow_label.visible = false
	_attachment_node.add_child(_energy_overflow_label)

	_tool_icon_disc = _make_disc_mesh(AttachmentDisplay.TOOL_ICON_COLOR)
	_tool_icon_disc.name = "ToolDisc"
	_tool_icon_label = _make_icon_label()
	_tool_icon_label.name = "ToolLabel"
	_attachment_node.add_child(_tool_icon_disc)
	_attachment_node.add_child(_tool_icon_label)
	_tool_icon_disc.visible = false
	_tool_icon_label.visible = false

	_layout_attachments()


func _layout_attachments() -> void:
	if _attachment_node == null:
		return
	var card_w: float = display_width
	var card_h: float = display_width / Card.BOARD_ART_RATIO
	var disc_radius: float = AttachmentDisplay.ENERGY_NORM_STEP_X * card_w * 0.40
	var disc_y: float = 0.012
	var label_y: float = 0.024

	for i in range(AttachmentDisplay.MAX_VISIBLE_ENERGY):
		var norm_x: float = AttachmentDisplay.ENERGY_NORM_START_X + i * AttachmentDisplay.ENERGY_NORM_STEP_X
		var ix: float = -card_w * 0.5 + norm_x * card_w
		var iz: float = -card_h * 0.5 + AttachmentDisplay.ENERGY_NORM_Y * card_h
		var disc := _energy_icon_discs[i]
		var cyl := disc.mesh as CylinderMesh
		cyl.top_radius = disc_radius
		cyl.bottom_radius = disc_radius
		disc.position = Vector3(ix, disc_y, iz)
		_energy_icon_labels[i].position = Vector3(ix, label_y, iz)

	var overflow_norm_x: float = (
		AttachmentDisplay.ENERGY_NORM_START_X
		+ AttachmentDisplay.MAX_VISIBLE_ENERGY * AttachmentDisplay.ENERGY_NORM_STEP_X
	)
	var overflow_x: float = -card_w * 0.5 + overflow_norm_x * card_w
	var overflow_z: float = -card_h * 0.5 + AttachmentDisplay.ENERGY_NORM_Y * card_h
	if _energy_overflow_disc != null:
		var ocyl := _energy_overflow_disc.mesh as CylinderMesh
		ocyl.top_radius = disc_radius
		ocyl.bottom_radius = disc_radius
		_energy_overflow_disc.position = Vector3(overflow_x, disc_y, overflow_z)
	_energy_overflow_label.position = Vector3(overflow_x, label_y, overflow_z)

	var tool_x: float = -card_w * 0.5 + AttachmentDisplay.TOOL_NORM_X * card_w
	var tool_z: float = -card_h * 0.5 + AttachmentDisplay.TOOL_NORM_START_Y * card_h
	if _tool_icon_disc != null:
		var tcyl := _tool_icon_disc.mesh as CylinderMesh
		tcyl.top_radius = disc_radius
		tcyl.bottom_radius = disc_radius
		_tool_icon_disc.position = Vector3(tool_x, disc_y, tool_z)
	if _tool_icon_label != null:
		_tool_icon_label.position = Vector3(tool_x, label_y, tool_z)


func _refresh_attachments() -> void:
	if _attachment_node == null:
		return
	var pokemon_type := card.pokemon_type if card != null else PokemonCardData.EnergyType.NONE
	var sorted: Array[CardData] = AttachmentDisplay.sort_energy(attached_energy, pokemon_type)
	var visible_count: int = mini(sorted.size(), AttachmentDisplay.MAX_VISIBLE_ENERGY)
	var overflow_count: int = sorted.size() - visible_count

	for i in range(AttachmentDisplay.MAX_VISIBLE_ENERGY):
		var disc := _energy_icon_discs[i]
		var lbl  := _energy_icon_labels[i]
		if i < visible_count:
			_apply_disc_to_energy(disc, lbl, sorted[i])
		else:
			disc.visible = false
			lbl.visible  = false

	var show_overflow := overflow_count > 0
	if _energy_overflow_disc != null:
		_energy_overflow_disc.visible = show_overflow
	_energy_overflow_label.visible = show_overflow

	var has_tool := not attached_tools.is_empty()
	if _tool_icon_disc != null:
		_tool_icon_disc.visible = has_tool
	if _tool_icon_label != null:
		_tool_icon_label.text = attached_tools[0].display_name.substr(0, 1) if has_tool else ""
		_tool_icon_label.visible = has_tool


## Applies either a cropped-art texture or the fallback solid-colour+letter
## to one energy attachment disc.
func _apply_disc_to_energy(disc: MeshInstance3D, lbl: Label3D, card_data: CardData) -> void:
	var mat := disc.get_surface_override_material(0) as StandardMaterial3D
	disc.visible = true
	if card_data.art != null:
		var crop: Dictionary = AttachmentDisplay.sphere_crop(card_data)
		var center: Vector2 = crop["center"]
		var r: float        = crop["radius"]
		## r is defined as a fraction of card WIDTH.  The y UV axis spans the
		## full card height, so we scale it down by the aspect ratio to keep
		## the crop square in pixel space (and the sphere circular on the disc).
		var aspect: float = (card_data.art.get_width() as float) \
				/ (card_data.art.get_height() as float)
		mat.albedo_texture = card_data.art
		mat.albedo_color   = Color.WHITE
		mat.uv1_scale      = Vector3(2.0 * r, 2.0 * r * aspect, 1.0)
		mat.uv1_offset     = Vector3(center.x - r, center.y - r * aspect, 0.0)
		lbl.visible = false
	else:
		mat.albedo_texture = null
		mat.albedo_color   = AttachmentDisplay.energy_color(card_data)
		mat.uv1_scale      = Vector3(1.0, 1.0, 1.0)
		mat.uv1_offset     = Vector3.ZERO
		lbl.text    = AttachmentDisplay.energy_label(card_data)
		lbl.visible = true


static func _make_disc_mesh(color: Color) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.height = 0.005
	cyl.radial_segments = 16
	mesh_inst.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.set_surface_override_material(0, mat)
	return mesh_inst


static func _make_icon_label() -> Label3D:
	var lbl := Label3D.new()
	lbl.pixel_size = 0.0009
	lbl.font_size = 22
	lbl.modulate = Color.WHITE
	lbl.outline_size = 5
	lbl.outline_modulate = Color.BLACK
	lbl.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	return lbl


## --- Conditions text ---------------------------------------------------------

func _conditions_text() -> String:
	## PSN and BRN are covered by badge disc visuals; only emit Group B text.
	var parts: Array[String] = []
	for c in special_conditions:
		if c == SpecialCondition.POISONED or c == SpecialCondition.BURNED:
			continue
		parts.append(_cond_abbrev(c))
	return " ".join(parts)


static func _cond_abbrev(c: int) -> String:
	match c:
		SpecialCondition.ASLEEP:    return "SLP"
		SpecialCondition.BURNED:    return "BRN"
		SpecialCondition.CONFUSED:  return "CNF"
		SpecialCondition.PARALYZED: return "PAR"
		SpecialCondition.POISONED:  return "PSN"
	return "?"


## --- Mutators (no legality checks — Manager is responsible) -----------------

func apply_damage(amount: int) -> void:
	current_hp = maxi(0, current_hp - maxi(0, amount))
	refresh_visual()


func heal(amount: int) -> void:
	current_hp = mini(max_hp, current_hp + maxi(0, amount))
	refresh_visual()


func add_condition(c: SpecialCondition) -> void:
	if not special_conditions.has(c):
		special_conditions.append(c)
	refresh_visual()


func remove_condition(c: SpecialCondition) -> void:
	special_conditions.erase(c)
	refresh_visual()


func attach_energy(energy_card: CardData) -> void:
	attached_energy.append(energy_card)
	refresh_visual()


func attach_tool(tool_card: CardData) -> void:
	attached_tools.append(tool_card)
	refresh_visual()


## Replaces the full energy list from an authoritative state snapshot (e.g.
## delivered by an online server delta).  Prefer individual attach_energy()
## calls for incremental mutations during local play.
func set_energy(energy: Array[CardData]) -> void:
	attached_energy = energy.duplicate()
	refresh_visual()


## Replaces the full tool list from an authoritative state snapshot.
func set_tools(tools: Array[CardData]) -> void:
	attached_tools = tools.duplicate()
	refresh_visual()


## Pushes [new_card] onto the evolution stack; the previous top becomes a
## prior stage.  Max HP updates; damage carries over.
func evolve_to(new_card: PokemonCardData) -> void:
	if card != null:
		prior_stages.append(card)
	card = new_card
	var carried_damage := max_hp - current_hp
	max_hp = new_card.hp_max if new_card != null else max_hp
	current_hp = maxi(0, max_hp - carried_damage)
	refresh_visual()


func is_knocked_out() -> bool:
	return current_hp <= 0


## Returns every card currently contained in this instance, in the order:
##   [top card, ...prior stages, ...attached energy, ...attached tools]
func all_cards() -> Array[CardData]:
	var out: Array[CardData] = []
	if card != null:
		out.append(card)
	for c in prior_stages:
		out.append(c)
	for e in attached_energy:
		out.append(e)
	for t in attached_tools:
		out.append(t)
	return out


## Detaches and returns every card; zeroes out dynamic state.  The caller is
## expected to route the returned cards into a specified list (discard, lost
## zone, etc.).  After this call the instance is safe to queue_free.
func release_cards() -> Array[CardData]:
	var out := all_cards()
	card = null
	prior_stages.clear()
	attached_energy.clear()
	attached_tools.clear()
	special_conditions.clear()
	modifiers.clear()
	current_hp = 0
	max_hp = 0
	return out


func set_display_width(w: float) -> void:
	display_width = w
	if _card_visual != null:
		_card_visual.set_display_width(w)
		_card_visual.set_board_mode(true)
	_layout_nameplate()
	_layout_attachments()
	_layout_status_halo()
	_layout_condition_badges()
	if _condition_label != null:
		_condition_label.position = Vector3(w * 0.30, 0.03, w * 0.18)

class_name Card
extends Node3D
## A 3D draggable card. Picked via raycast on its StaticBody3D.
## The visible face is rendered into a SubViewport and displayed on a PlaneMesh
## that sits just above the card body.

signal drag_started(card: Card)
signal drag_ended(card: Card)
signal card_dropped(card: Card)

@export var card_name: String = "Card"
## Texture shown on the card face mesh when the card is face-down.
## Falls back to BACK_COLOR if not set.
@export var back_texture: Texture2D = null

## Runtime card data binding
var card_instance: CardInstance = null

## Card dimensions (roughly standard playing card proportions)
const CARD_WIDTH := 0.63
const CARD_HEIGHT := 0.88
const CARD_THICKNESS := 0.01

## Visual settings
const HOVER_LIFT := 0.15
const DRAG_LIFT := 0.3
const TWEEN_SPEED := 0.15
const DRAW_SPEED := 0.5

## Colour shown on the face mesh when the card is face-down (back design).
const BACK_COLOR := Color(0.08, 0.12, 0.40)

## Tool icon layout (left edge of card).
const ICON_RADIUS := 0.08
const ICON_HEIGHT := 0.004
const ICON_Y := 0.012
const ICON_START_Z := -0.25
const ICON_SPACING := 0.20

## Energy icon layout (bottom edge of card, smaller than tool icons).
const ENERGY_ICON_RADIUS := 0.039   # ~half of ICON_RADIUS
const ENERGY_ICON_HEIGHT := 0.004
const ENERGY_ICON_MAX := 5          # max circles shown before overflow "+" indicator

## Overlay icon layout (right edge of card, for status badges).
const DAMAGE_CTR_RADIUS := 0.200
const STATUS_BADGE_RADIUS := 0.055
const OVERLAY_HEIGHT := 0.004
const OVERLAY_Y := 0.014

## Board mode: card shows only the painted art at landscape proportions.
## Art aspect ratio matches CardFace.BOARD_ART_RATIO (1.52 : 1).
const BOARD_ART_RATIO := 1.52
const BOARD_CARD_H    := 0.414   ## CARD_WIDTH / BOARD_ART_RATIO ≈ 0.414

## Nameplate strip shown above the card in board mode.
const NAMEPLATE_H := 0.13    ## strip height (world units)
const NAMEPLATE_Y := 0.014   ## Y lift above the card surface

const FACE_ROUNDED_SHADER := preload("res://scenes/card/card_face_rounded.gdshader")

## State
var is_dragging := false
var is_hovered := false

## True when the card is placed on an active or bench zone.
var _board_mode: bool = false
var _nameplate_node: Node3D = null

## Overlay nodes managed by update_status_overlays().
var _damage_ctr_node: Node3D = null
var _status_badge_nodes: Array[Node3D] = []
var face_down: bool = false:
	set(value):
		face_down = value
		_update_visuals()
var home_position := Vector3.ZERO
var home_rotation := Vector3.ZERO
var hand_index := 0

var _tween: Tween = null
var _face_material: StandardMaterial3D = null
var _body_material: StandardMaterial3D = null
var _face_shader_material: ShaderMaterial = null
## Holds an instance assigned before _ready() runs (nodes not yet available).
var _pending_instance: CardInstance = null

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var static_body: StaticBody3D = $StaticBody3D
@onready var face_viewport: SubViewport = $FaceViewport
@onready var card_face: CardFace = $FaceViewport/CardFace
@onready var face_mesh: MeshInstance3D = $FaceMesh


func _ready() -> void:
	## Build the face material once and keep a reference to swap textures on.
	_face_material = StandardMaterial3D.new()
	_face_material.albedo_color = BACK_COLOR
	_face_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	face_mesh.set_surface_override_material(0, _face_material)
	## Build the shader material used for face-up cards with art (rounded corners).
	_face_shader_material = ShaderMaterial.new()
	_face_shader_material.shader = FACE_ROUNDED_SHADER
	_face_shader_material.set_shader_parameter("corner_radius", 0.023)
	_face_shader_material.set_shader_parameter("card_size", Vector2(CARD_WIDTH, CARD_HEIGHT))
	## Duplicate the body material so each card owns its instance (for alpha toggling).
	var src := mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	_body_material = src.duplicate() as StandardMaterial3D
	mesh_instance.set_surface_override_material(0, _body_material)
	## Duplicate meshes so set_board_mode() can resize them without affecting the
	## shared .tscn resource (which all cards reference).
	face_mesh.mesh = face_mesh.mesh.duplicate()
	mesh_instance.mesh = mesh_instance.mesh.duplicate()
	## Apply any instance that was set before the node was in the tree.
	if _pending_instance != null:
		set_instance(_pending_instance)
		_pending_instance = null
	else:
		_update_visuals()


func set_instance(inst: CardInstance) -> void:
	if not is_node_ready():
		_pending_instance = inst
		card_instance = inst
		if inst and inst.data:
			card_name = inst.data.display_name
		return
	card_instance = inst
	if inst and inst.data:
		card_name = inst.data.display_name
		_queue_face_refresh()
	_update_visuals()


## Switches the card between board mode (landscape art + nameplate) and hand mode.
## Call with true when the card enters an active or bench zone; false when it leaves.
func set_board_mode(on: bool) -> void:
	_board_mode = on
	_resize_meshes(on)
	if on:
		_build_nameplate()
		if card_instance != null and card_instance.data != null:
			_queue_face_refresh()
	else:
		_remove_nameplate()
		if card_instance != null and card_instance.data != null:
			_queue_face_refresh()


## Resizes the face PlaneMesh and body BoxMesh for board mode (landscape art)
## or restores portrait dimensions when leaving board mode.
func _resize_meshes(board: bool) -> void:
	var new_h := BOARD_CARD_H if board else CARD_HEIGHT
	var plane := face_mesh.mesh as PlaneMesh
	plane.size = Vector2(CARD_WIDTH, new_h)
	var box := mesh_instance.mesh as BoxMesh
	box.size = Vector3(CARD_WIDTH, CARD_THICKNESS, new_h)
	_face_shader_material.set_shader_parameter("card_size", Vector2(CARD_WIDTH, new_h))


## Queues an async face refresh (fire-and-forget — do not await).
## Uses board mode (art crop) or hand mode (full image) based on _board_mode.
func _queue_face_refresh() -> void:
	if not is_node_ready() or card_instance == null or card_instance.data == null:
		return
	if _board_mode:
		card_face.setup_board(card_instance)
	else:
		card_face.setup(card_instance.data)
	## Wait two frames — one for layout, one for the SubViewport to render.
	## Guard each await: the card node may be freed (e.g. deck teardown).
	await get_tree().process_frame
	if not is_inside_tree():
		return
	face_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_update_visuals()


## Builds and attaches the 3D nameplate strip above the card's top edge.
## Shows name on the left and HP fraction on the right (Pokemon only).
func _build_nameplate() -> void:
	_remove_nameplate()
	if card_instance == null or card_instance.data == null:
		return

	_nameplate_node = Node3D.new()
	_nameplate_node.name = "Nameplate"

	## Dark background plane lying flat on the table.
	var bg := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(CARD_WIDTH, NAMEPLATE_H)
	bg.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.05, 0.90)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg.set_surface_override_material(0, mat)
	_nameplate_node.add_child(bg)

	## Name label — left side.
	var name_lbl := Label3D.new()
	name_lbl.name = "NameplateName"
	name_lbl.text = card_instance.data.display_name
	name_lbl.pixel_size = 0.00085
	name_lbl.font_size = 52
	name_lbl.modulate = Color.WHITE
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	## Rotate -90° around X so the label lies flat and reads from above.
	name_lbl.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	name_lbl.position = Vector3(-CARD_WIDTH * 0.5 + 0.035, 0.002, 0.0)
	_nameplate_node.add_child(name_lbl)

	## HP label — right side (Pokemon only).
	if card_instance.is_pokemon():
		var hp_lbl := Label3D.new()
		hp_lbl.name = "NameplateHP"
		hp_lbl.text = "%d/%d HP" % [card_instance.hp_remaining(), card_instance.hp_max()]
		hp_lbl.pixel_size = 0.00085
		hp_lbl.font_size = 42
		hp_lbl.modulate = Color.WHITE
		hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hp_lbl.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
		hp_lbl.position = Vector3(CARD_WIDTH * 0.5 - 0.035, 0.002, 0.0)
		_nameplate_node.add_child(hp_lbl)

	## Position just past the top edge of the board-mode (landscape) card.
	_nameplate_node.position = Vector3(
		0.0, NAMEPLATE_Y, -(BOARD_CARD_H * 0.5 + NAMEPLATE_H * 0.5)
	)
	add_child(_nameplate_node)


func _remove_nameplate() -> void:
	if _nameplate_node != null and is_instance_valid(_nameplate_node):
		_nameplate_node.queue_free()
	_nameplate_node = null


## Updates just the HP text on the nameplate without re-rendering the face.
func _update_nameplate_hp() -> void:
	if _nameplate_node == null or card_instance == null:
		return
	var hp_lbl := _nameplate_node.get_node_or_null("NameplateHP") as Label3D
	if hp_lbl != null:
		hp_lbl.text = "%d/%d HP" % [card_instance.hp_remaining(), card_instance.hp_max()]


func _update_visuals() -> void:
	if not _face_material:
		return
	if face_down or card_instance == null:
		## SleevesManager takes priority; fall back to back_texture export, then BACK_COLOR.
		var owner_id: int = card_instance.owner_id if card_instance != null else 0
		var back_tex: Texture2D = SleevesManager.get_sleeve(owner_id)
		if back_tex == null:
			back_tex = back_texture
		## Ensure the standard material is active on the face mesh (may have been
		## replaced by the shader material while the card was face-up).
		face_mesh.set_surface_override_material(0, _face_material)
		if back_tex != null:
			## Texture-based back: honour the image's alpha channel for rounded corners.
			## ALPHA_SCISSOR clips pixels cleanly without depth-sort issues on stacked cards.
			_face_material.albedo_texture = back_tex
			_face_material.albedo_color = Color.WHITE
			_face_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			_face_material.alpha_scissor_threshold = 0.5
			## Hide the body mesh so its opaque top face doesn't bleed through the clipped corners.
			if _body_material:
				_body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_body_material.albedo_color.a = 0.0
		else:
			## Solid-colour fallback — keep everything opaque (rectangular card shape).
			_face_material.albedo_texture = null
			_face_material.albedo_color = BACK_COLOR
			_face_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			if _body_material:
				_body_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				_body_material.albedo_color.a = 1.0
	else:
		## Face-up: use the rounded-corner shader material so the card silhouette
		## matches the card_back.  Corner regions sample mirrored edge content
		## rather than cutting off the card border abruptly.
		_face_shader_material.set_shader_parameter("face_texture", face_viewport.get_texture())
		face_mesh.set_surface_override_material(0, _face_shader_material)
		## Hide the body mesh so its rectangular corners don't show through the
		## clipped face, mirroring the card-back treatment.
		if _body_material:
			_body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_body_material.albedo_color.a = 0.0


func set_hovered(value: bool) -> void:
	if value == is_hovered or is_dragging:
		return
	is_hovered = value
	if value:
		_on_hover_start()
	else:
		_on_hover_end()


func _new_tween() -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	return _tween


func start_drag() -> void:
	is_dragging = true
	is_hovered = false
	var tween := _new_tween()
	tween.tween_property(self, "position:y", home_position.y + DRAG_LIFT, TWEEN_SPEED)
	tween.tween_property(self, "rotation", Vector3(0, home_rotation.y, home_rotation.z), TWEEN_SPEED)
	drag_started.emit(self)


func end_drag() -> void:
	if not is_dragging:
		return
	is_dragging = false
	card_dropped.emit(self)
	drag_ended.emit(self)


func move_to_drag_position(world_pos: Vector3) -> void:
	global_position = Vector3(world_pos.x, home_position.y + DRAG_LIFT, world_pos.z)


func _on_hover_start() -> void:
	var tween := _new_tween()
	tween.tween_property(self, "position:y", home_position.y + HOVER_LIFT, TWEEN_SPEED)
	tween.tween_property(self, "rotation", Vector3(0, home_rotation.y, home_rotation.z), TWEEN_SPEED)


func _on_hover_end() -> void:
	return_to_home()


func return_to_home() -> void:
	var tween := _new_tween()
	tween.tween_property(self, "position", home_position, TWEEN_SPEED)
	tween.tween_property(self, "rotation", home_rotation, TWEEN_SPEED)


func animate_draw() -> void:
	var tween := _new_tween()
	tween.tween_property(self, "position", home_position, DRAW_SPEED) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation", home_rotation, DRAW_SPEED) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func snap_to_home() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	position = home_position
	rotation = home_rotation


func set_home(pos: Vector3, rot: Vector3, index: int) -> void:
	home_position = pos
	home_rotation = rot
	hand_index = index


## Rebuilds the small overlay circles showing attached energy and tools.
## Call this whenever the card's attached_energy or attached_tools change.
func update_attachment_icons() -> void:
	for child in get_children():
		if child.name.begins_with("AttachIcon_"):
			child.queue_free()
	if card_instance == null:
		return

	# Energy circles along the bottom edge in canonical order, left-justified.
	var sorted_energy := AttachmentDisplay.sort_energy(card_instance.attached_energy)
	var energy_count := sorted_energy.size()
	var visible_count: int = min(energy_count, ENERGY_ICON_MAX)

	for i in range(visible_count):
		_spawn_energy_icon(sorted_energy[i], _energy_pos_x(i), i)
	if energy_count > ENERGY_ICON_MAX:
		_spawn_energy_overflow(_energy_pos_x(ENERGY_ICON_MAX))

	# Tool circles on the left edge (unchanged layout).
	for i in range(card_instance.attached_tools.size()):
		_spawn_tool_icon(card_instance.attached_tools[i], i)


## Returns the 3D x coordinate for energy icon at [slot], left-justified from
## the weakness-symbol area using the shared normalised fractions.
func _energy_pos_x(slot: int) -> float:
	var frac := AttachmentDisplay.ENERGY_NORM_START_X + slot * AttachmentDisplay.ENERGY_NORM_STEP_X
	return -CARD_WIDTH * 0.5 + CARD_WIDTH * frac


func _spawn_energy_icon(inst: CardInstance, x: float, index: int) -> void:
	var icon := Node3D.new()
	icon.name = "AttachIcon_E%d" % index

	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = ENERGY_ICON_RADIUS
	cyl.bottom_radius = ENERGY_ICON_RADIUS
	cyl.height = ENERGY_ICON_HEIGHT
	disc.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = AttachmentDisplay.energy_color(inst)
	disc.set_surface_override_material(0, mat)
	icon.add_child(disc)

	var lbl := Label3D.new()
	lbl.text = AttachmentDisplay.energy_label(inst)
	lbl.pixel_size = 0.0006
	lbl.font_size = 22
	lbl.modulate = Color.WHITE
	lbl.position = Vector3(0.0, ENERGY_ICON_HEIGHT * 0.5 + 0.001, 0.0)
	icon.add_child(lbl)

	# Centre the disc on the bottom edge — 50% overlap.
	icon.position = Vector3(x, ICON_Y, CARD_HEIGHT * 0.5)
	add_child(icon)


## Spawns a "+" text indicator after the fifth energy circle when 6+ are attached.
func _spawn_energy_overflow(x: float) -> void:
	var icon := Node3D.new()
	icon.name = "AttachIcon_EOverflow"

	var lbl := Label3D.new()
	lbl.text = "+"
	lbl.pixel_size = 0.0008
	lbl.font_size = 28
	lbl.modulate = Color.WHITE
	icon.add_child(lbl)

	icon.position = Vector3(x, ICON_Y, CARD_HEIGHT * 0.5)
	add_child(icon)


## Updates the HP display after damage changes.
## HP is shown in the nameplate (no 3D disc overlay); just refreshes the label text.
func update_damage_counter() -> void:
	if _damage_ctr_node != null and is_instance_valid(_damage_ctr_node):
		_damage_ctr_node.queue_free()
	_damage_ctr_node = null
	_update_nameplate_hp()


## Updates the status condition badges (PSN, BRN, etc.) on the right edge.
## Call whenever special_conditions change or the card becomes face-up/down.
func update_status_overlays() -> void:
	for node in _status_badge_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_status_badge_nodes.clear()

	if card_instance == null or face_down:
		return

	var badges: Array[Dictionary] = []
	if card_instance.has_condition(CardInstance.SpecialCondition.POISONED):
		badges.append({"label": "PSN", "color": Color(0.62, 0.08, 0.82, 0.92)})
	if card_instance.has_condition(CardInstance.SpecialCondition.BURNED):
		badges.append({"label": "BRN", "color": Color(0.95, 0.38, 0.04, 0.92)})
	if card_instance.has_condition(CardInstance.SpecialCondition.PARALYZED):
		badges.append({"label": "PAR", "color": Color(0.90, 0.85, 0.08, 0.92)})
	if card_instance.has_condition(CardInstance.SpecialCondition.ASLEEP):
		badges.append({"label": "SLP", "color": Color(0.28, 0.28, 0.68, 0.92)})
	if card_instance.has_condition(CardInstance.SpecialCondition.CONFUSED):
		badges.append({"label": "CNF", "color": Color(0.78, 0.38, 0.68, 0.92)})

	## Stack badges down the right edge, starting just below the damage counter.
	var badge_start_z := -(CARD_HEIGHT * 0.5 - DAMAGE_CTR_RADIUS * 2.0 - STATUS_BADGE_RADIUS)
	for i in range(badges.size()):
		var badge: Dictionary = badges[i]
		var node := _spawn_status_badge(
			badge["label"] as String,
			badge["color"] as Color,
			badge_start_z + i * (STATUS_BADGE_RADIUS * 2.2 + 0.008)
		)
		add_child(node)
		_status_badge_nodes.append(node)


func _spawn_status_badge(lbl_text: String, color: Color, z_pos: float) -> Node3D:
	var node := Node3D.new()
	node.name = "StatusBadge_%s" % lbl_text

	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = STATUS_BADGE_RADIUS
	cyl.bottom_radius = STATUS_BADGE_RADIUS
	cyl.height = OVERLAY_HEIGHT
	disc.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.set_surface_override_material(0, mat)
	node.add_child(disc)

	var lbl := Label3D.new()
	lbl.text = lbl_text
	lbl.pixel_size = 0.00060
	lbl.font_size = 18
	lbl.modulate = Color.WHITE
	lbl.position = Vector3(0.0, OVERLAY_HEIGHT * 0.5 + 0.001, 0.0)
	node.add_child(lbl)

	node.position = Vector3(CARD_WIDTH * 0.5 - STATUS_BADGE_RADIUS, OVERLAY_Y, z_pos)
	return node


func _spawn_tool_icon(inst: CardInstance, index: int) -> void:
	var icon := Node3D.new()
	icon.name = "AttachIcon_T%d" % index

	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = ICON_RADIUS
	cyl.bottom_radius = ICON_RADIUS
	cyl.height = ICON_HEIGHT
	disc.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = AttachmentDisplay.TOOL_ICON_COLOR
	disc.set_surface_override_material(0, mat)
	icon.add_child(disc)

	var lbl := Label3D.new()
	lbl.text = "T"
	lbl.pixel_size = 0.0018
	lbl.font_size = 22
	lbl.modulate = Color.WHITE
	lbl.position = Vector3(0.0, ICON_HEIGHT * 0.5 + 0.001, 0.0)
	icon.add_child(lbl)

	icon.position = Vector3(
		-(CARD_WIDTH * 0.5),
		ICON_Y,
		ICON_START_Z + index * ICON_SPACING
	)
	add_child(icon)

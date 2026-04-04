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

## State
var is_dragging := false
var is_hovered := false
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
	## Duplicate the body material so each card owns its instance (for alpha toggling).
	var src := mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	_body_material = src.duplicate() as StandardMaterial3D
	mesh_instance.set_surface_override_material(0, _body_material)
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
		card_face.setup(inst.data)
		## Wait two frames — one for layout, one for the SubViewport to render.
		## Guard each await: the card node may be freed (e.g. deck teardown) before
		## the frame completes, which would cause a call on a freed instance.
		await get_tree().process_frame
		if not is_inside_tree():
			return
		face_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await get_tree().process_frame
		if not is_inside_tree():
			return
	_update_visuals()


func _update_visuals() -> void:
	if not _face_material:
		return
	if face_down or card_instance == null:
		## SleevesManager takes priority; fall back to back_texture export, then BACK_COLOR.
		var owner_id: int = card_instance.owner_id if card_instance != null else 0
		var back_tex: Texture2D = SleevesManager.get_sleeve(owner_id)
		if back_tex == null:
			back_tex = back_texture
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
		_face_material.albedo_texture = face_viewport.get_texture()
		_face_material.albedo_color = Color.WHITE
		_face_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		if _body_material:
			_body_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			_body_material.albedo_color.a = 1.0


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
	var visible_count := min(energy_count, ENERGY_ICON_MAX)

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

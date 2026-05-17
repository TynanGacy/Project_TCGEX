extends Node3D
## Generates simple primitive colliders (cylinders, boxes) for an imported
## environment model, classified by each mesh's world-space dimensions and
## position. Trades exact-mesh accuracy for predictable physics behaviour:
## the player can't get wedged on a complex shape, the solver doesn't choke
## on many overlapping trimesh contacts, and decorations that should just
## be "ambient" (canopy foliage, godrays, ground litter) end up with no
## collision at all.
##
## Skinned meshes (FSYS imports from Pokemon XD / Colosseum) place their
## geometry via the Skeleton3D's bones, with each `MeshInstance3D` sitting
## at local (0,0,0). We mirror the renderer's transform chain so the
## generated primitive lands where the mesh actually appears:
##   world = skeleton_global × bone_global_pose × bind_pose × mesh_local
## A `BoneAttachment3D` carries the bone pose; the StaticBody3D's local
## transform carries the bind pose offset.
##
## Classification (run after computing each mesh's world-space AABB):
##   - Bottom above `skip_above_world_y`   → SKIP (canopy / godrays)
##   - Footprint AND height very small     → SKIP (lilypads, pebbles)
##   - Tall AND narrow at ground            → TRUNK  (CylinderShape3D)
##   - Anything else at ground              → BOX    (BoxShape3D)
##
## Tune the thresholds via the export vars below; defaults work for the
## kakutyou1 relic-shrine model.

enum CollisionKind { SKIP, TRUNK, BOX }

@export var collision_layer: int = 4  ## Bit value 4 == Layer 3 (ow_world).

@export_group("Filters")
## Mesh's lowest world-Y must be at or below this. Above = canopy / godrays.
@export var skip_above_world_y: float = 2.5
## Small ground decoration: max(X, Z) below this AND height below
## `small_decoration_max_y`. Filters lilypads, gravel, etc.
@export var small_decoration_max_xz: float = 1.5
@export var small_decoration_max_y: float = 0.3
## Skip huge meshes whose any dimension exceeds this — these are usually
## skybox domes / world-spanning terrain that would swallow the player as
## a solid box. The walkway floor is ~21m long so threshold clears that
## while still catching the ~100m skybox.
@export var skip_above_size: float = 50.0
## Skip "tall AND wide" boxes — terrain backdrops are several metres thick
## in Y AND span many metres horizontally. Real floor tiles are thin (Y
## under a couple metres); trees are tall but narrow and go through the
## trunk path first. A box that fails BOTH conditions is almost certainly
## an environment volume the player shouldn't be standing inside of.
@export var bulky_box_max_height: float = 5.0
@export var bulky_box_max_footprint: float = 15.0

@export_group("Trunk classification")
## Mesh height (Y) at or above this counts as "tall".
@export var trunk_min_height: float = 1.5
## Mesh max(X, Z) at or below this counts as "narrow". Combined with
## `trunk_min_height` to classify a mesh as a tree trunk → cylinder.
@export var trunk_max_radius: float = 1.5
## Cylinder radius inflated by this much, so the player doesn't hug the
## visual silhouette and get stuck on tangential collisions.
@export var trunk_radius_padding: float = 0.05

@export_group("Box / floor")
## Minimum thickness applied to flat box colliders. Real geometry can be
## paper-thin and tunnel; this guarantees solidity for fast-moving bodies.
@export var box_min_thickness: float = 0.3

@export var verbose: bool = false
## When true, attach a transparent wireframe MeshInstance3D next to each
## collider so you can see what the script generated.
@export var debug_visualize: bool = false


func _ready() -> void:
	# Defer one frame so the Skeleton3D has finished initializing its pose.
	await get_tree().process_frame

	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(self, meshes)
	if verbose:
		print("[AutoCollider] scanning %d meshes under %s" % [meshes.size(), name])

	var counts: Dictionary = {
		CollisionKind.SKIP: 0,
		CollisionKind.TRUNK: 0,
		CollisionKind.BOX: 0,
	}
	var skipped_no_mesh: int = 0
	for mi in meshes:
		var mesh: Mesh = mi.mesh
		if mesh == null:
			skipped_no_mesh += 1
			continue
		var aabb: AABB = mesh.get_aabb()
		var xform: Transform3D = _resolve_skinned_world_transform(mi)
		var world_bottom_y: float = _world_aabb_bottom_y(aabb, xform)
		var kind: int = _classify(aabb, world_bottom_y)
		counts[kind] += 1
		if verbose:
			print("  %s — size=(%.2f, %.2f, %.2f), bot_y=%.2f → %s" % [
				mi.name, aabb.size.x, aabb.size.y, aabb.size.z, world_bottom_y,
				_kind_name(kind),
			])
		match kind:
			CollisionKind.SKIP:
				continue
			CollisionKind.TRUNK:
				_attach_trunk_collider(mi, aabb)
			CollisionKind.BOX:
				_attach_box_collider(mi, aabb)

	print("[AutoCollider] %s: trunks=%d boxes=%d skipped=%d no_mesh=%d" % [
		name,
		counts[CollisionKind.TRUNK], counts[CollisionKind.BOX],
		counts[CollisionKind.SKIP], skipped_no_mesh,
	])


func _classify(aabb: AABB, world_bottom_y: float) -> int:
	var s: Vector3 = aabb.size
	if skip_above_size > 0.0 and maxf(maxf(s.x, s.y), s.z) > skip_above_size:
		return CollisionKind.SKIP
	if skip_above_world_y >= 0.0 and world_bottom_y > skip_above_world_y:
		return CollisionKind.SKIP
	var max_xz: float = maxf(s.x, s.z)
	if max_xz <= small_decoration_max_xz and s.y <= small_decoration_max_y:
		return CollisionKind.SKIP
	if s.y >= trunk_min_height and max_xz <= trunk_max_radius:
		return CollisionKind.TRUNK
	# Bulky environment volume (terrain backdrop) — would enclose the player.
	if s.y > bulky_box_max_height and max_xz > bulky_box_max_footprint:
		return CollisionKind.SKIP
	return CollisionKind.BOX


func _attach_trunk_collider(mi: MeshInstance3D, aabb: AABB) -> void:
	var radius: float = maxf(aabb.size.x, aabb.size.z) * 0.5 + trunk_radius_padding
	var height: float = aabb.size.y
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var local_center: Vector3 = aabb.position + aabb.size * 0.5
	var body: StaticBody3D = _attach_shape(mi, shape, local_center)
	if debug_visualize and body != null:
		var viz_mesh: CylinderMesh = CylinderMesh.new()
		viz_mesh.top_radius = radius
		viz_mesh.bottom_radius = radius
		viz_mesh.height = height
		_add_debug_mesh(body, viz_mesh, Color(1, 0.4, 0.2, 0.4))


func _attach_box_collider(mi: MeshInstance3D, aabb: AABB) -> void:
	var size: Vector3 = aabb.size
	size.y = maxf(size.y, box_min_thickness)
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var local_center: Vector3 = aabb.position + aabb.size * 0.5
	var body: StaticBody3D = _attach_shape(mi, shape, local_center)
	if debug_visualize and body != null:
		var viz_mesh: BoxMesh = BoxMesh.new()
		viz_mesh.size = size
		_add_debug_mesh(body, viz_mesh, Color(0.3, 0.8, 0.3, 0.35))


func _add_debug_mesh(body: StaticBody3D, mesh: Mesh, color: Color) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi_viz: MeshInstance3D = MeshInstance3D.new()
	mi_viz.mesh = mesh
	mi_viz.material_override = mat
	body.add_child(mi_viz)


## Position the StaticBody3D so that `local_center` (mesh-local) lands at
## the same world position the renderer puts that point at. Returns the
## body so callers can add debug visualizers as children.
func _attach_shape(mi: MeshInstance3D, shape: Shape3D, local_center: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = collision_layer
	body.collision_mask = 0
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)

	var skel_path: NodePath = mi.skeleton
	var skel: Skeleton3D = null
	if skel_path != NodePath(""):
		skel = mi.get_node_or_null(skel_path) as Skeleton3D
	var skin: Skin = mi.skin
	if skel == null or skin == null or skin.get_bind_count() == 0:
		mi.add_child(body)
		body.position = local_center
		return body

	var bone_idx: int = _resolve_bone(skel, skin)
	if bone_idx < 0:
		mi.add_child(body)
		body.position = local_center
		return body

	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	attachment.bone_idx = bone_idx
	skel.add_child(attachment)
	attachment.add_child(body)
	# bind_pose × translate(local_center) = where the renderer puts that
	# point relative to the bone, which is where we want the shape's centre.
	body.transform = skin.get_bind_pose(0) * Transform3D(Basis.IDENTITY, local_center)
	return body


func _resolve_skinned_world_transform(mi: MeshInstance3D) -> Transform3D:
	var skel_path: NodePath = mi.skeleton
	if skel_path == NodePath(""):
		return mi.global_transform
	var skel: Skeleton3D = mi.get_node_or_null(skel_path) as Skeleton3D
	var skin: Skin = mi.skin
	if skel == null or skin == null or skin.get_bind_count() == 0:
		return mi.global_transform
	var bone_idx: int = _resolve_bone(skel, skin)
	if bone_idx < 0:
		return mi.global_transform
	return skel.global_transform * skel.get_bone_global_pose(bone_idx) * skin.get_bind_pose(0)


func _resolve_bone(skel: Skeleton3D, skin: Skin) -> int:
	var idx: int = skin.get_bind_bone(0)
	if idx >= 0:
		return idx
	var bone_name: StringName = skin.get_bind_name(0)
	if bone_name == &"":
		return -1
	return skel.find_bone(bone_name)


func _world_aabb_bottom_y(local_aabb: AABB, xform: Transform3D) -> float:
	var min_y: float = INF
	for i in 8:
		var corner: Vector3 = local_aabb.position + Vector3(
			local_aabb.size.x if (i & 1) else 0.0,
			local_aabb.size.y if (i & 2) else 0.0,
			local_aabb.size.z if (i & 4) else 0.0,
		)
		var world_corner: Vector3 = xform * corner
		min_y = minf(min_y, world_corner.y)
	return min_y


func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out)


func _kind_name(kind: int) -> String:
	match kind:
		CollisionKind.TRUNK: return "TRUNK"
		CollisionKind.BOX:   return "BOX"
		_:                   return "skip"

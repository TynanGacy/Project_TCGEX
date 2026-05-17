extends StaticBody3D
## Terrain gate — a generic HM-style barrier.
##
## Blocks the player until `OverworldInventory.has(required_item)` is true.
## Use one node per logical gate; the same scene covers sea / mountain /
## rocky barrier / etc. by swapping the visual mesh.
##
## The collider lives on Layer 5 (`ow_gates`); the player's mask includes
## that layer so the gate stops them. When unlocked, the collider is
## disabled and the visual is hidden.

@export var required_item: StringName = &""
## If true, gate disappears entirely once unlocked. If false, stays as a
## visual marker but no longer blocks (e.g. open doorways).
@export var hide_when_unlocked: bool = true

@onready var _collider: CollisionShape3D = $CollisionShape3D
@onready var _visual: Node3D = $Visual


func _ready() -> void:
	add_to_group(&"ow_gates")
	OverworldInventory.item_granted.connect(_on_item_granted)
	_refresh()


func _on_item_granted(item: StringName) -> void:
	if item == required_item:
		_refresh()


func _refresh() -> void:
	var unlocked: bool = required_item == &"" or OverworldInventory.has(required_item)
	_collider.disabled = unlocked
	if hide_when_unlocked:
		_visual.visible = not unlocked

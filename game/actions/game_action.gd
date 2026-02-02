# res://game/actions/GameAction.gd
class_name GameAction
extends RefCounted

# Who is performing this action (0/1, or however you index players).
var actor_id: int = -1

func validate(state) -> ActionResult:
	# Override in subclasses.
	return ActionResult.success()

func apply(state) -> void:
	# Override in subclasses.
	pass

func description() -> String:
	# Override for log readability.
	return "GameAction"

class_name GameAction
extends RefCounted

var actor_id: int = -1

func validate(_state: GameState) -> ActionResult:
	return ActionResult.success()

func apply(_state: GameState) -> void:
	pass

func description() -> String:
	return "GameAction"

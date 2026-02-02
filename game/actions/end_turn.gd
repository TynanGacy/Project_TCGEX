# res://game/actions/ActionEndTurn.gd
class_name ActionEndTurn
extends GameAction

func _init(actor: int = -1) -> void:
	actor_id = actor

func validate(state: GameState) -> ActionResult:
	if state.phase != TurnPhase.Phase.END:
		return ActionResult.fail("Can only end turn during END phase.")
	return ActionResult.success()

func apply(state: GameState) -> void:
	state.end_turn()

func description() -> String:
	return "End turn"

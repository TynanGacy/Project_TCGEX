class_name ActionAdvancePhase
extends GameAction

func _init(actor: int = -1) -> void:
	actor_id = actor

func validate(state: GameState) -> ActionResult:
	if state.phase == TurnPhase.Phase.END:
		return ActionResult.fail("Cannot advance phase from END. End the turn.")
	return ActionResult.success()

func apply(state: GameState) -> void:
	state.advance_phase()

func description() -> String:
	return "Advance phase"

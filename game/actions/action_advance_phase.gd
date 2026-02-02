# res://game/actions/ActionAdvancePhase.gd
class_name ActionAdvancePhase
extends GameAction

func _init(actor: int = -1) -> void:
	actor_id = actor

func validate(state: GameState) -> ActionResult:
	# You can restrict skipping phases if desired.
	if state.phase == TurnPhase.Phase.END:
		return ActionResult.fail("Cannot advance phase from END. End the turn.")
	return ActionResult.success()

func apply(state: GameState) -> void:
	state.advance_phase()
	# TurnController is the one emitting phase_changed right now only on start;
	# either emit it there on commit, or let UI listen to action_committed and refresh.
	# Minimal approach: TurnController can watch for this action type and emit phase_changed.
	# But we keep actions pure; instead, the UI can refresh from state on action_committed.

func description() -> String:
	return "Advance phase"

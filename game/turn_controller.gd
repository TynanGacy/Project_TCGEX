# res://game/TurnController.gd
class_name TurnController
extends Node

signal turn_started(turn_number: int, current_player_id: int)
signal phase_changed(phase: int)
signal action_committed(action: GameAction)
signal action_rejected(action: GameAction, reason: String)

# Optional: for debug/UI log panel
signal log_message(text: String)

var state: GameState

func _ready() -> void:
	# You can inject your real GameState from a higher-level Game node.
	# For now, create one if none exists.
	if state == null:
		state = GameState.new()
	_start_turn(state.current_player_id)

func set_state(gs: GameState) -> void:
	state = gs

func request_action(action: GameAction) -> void:
	if state == null:
		_emit_reject(action, "No GameState assigned.")
		return

	# Universal gating: correct actor and basic phase rules.
	var gate := _gate_action(action)
	if not gate.ok:
		_emit_reject(action, gate.reason)
		return

	# Action-specific validation:
	var res := action.validate(state)
	if not res.ok:
		_emit_reject(action, res.reason)
		return

	# Apply and announce:
	action.apply(state)
	emit_signal("action_committed", action)

	# After apply:
	if action is ActionAdvancePhase:
		emit_signal("phase_changed", state.phase)

	if action is ActionEndTurn:
		# state.end_turn() already advanced to next player's START.
		emit_signal("turn_started", state.turn_number, state.current_player_id)
		emit_signal("phase_changed", state.phase)

	emit_signal("log_message", "[P%d][%s] %s" % [
		action.actor_id,
		TurnPhase.phase_to_string(state.phase),
		action.description()
	])

func next_phase(actor_id: int) -> void:
	request_action(ActionAdvancePhase.new(actor_id))

func end_turn(actor_id: int) -> void:
	request_action(ActionEndTurn.new(actor_id))

# -------------------
# Internal helpers
# -------------------
func _start_turn(player_id: int) -> void:
	state.begin_turn(player_id)
	emit_signal("turn_started", state.turn_number, state.current_player_id)
	emit_signal("phase_changed", state.phase)
	emit_signal("log_message", "Turn %d start: Player %d" % [state.turn_number, state.current_player_id])

func _emit_reject(action: GameAction, reason: String) -> void:
	emit_signal("action_rejected", action, reason)
	emit_signal("log_message", "[REJECT] %s (%s)" % [action.description(), reason])

func _gate_action(action: GameAction) -> ActionResult:
	# Ensure actor is the current player (for now).
	if action.actor_id != state.current_player_id:
		return ActionResult.fail("Not your turn.")

	# Optional: phase gating can be centralized here for broad categories.
	# Specific actions can still validate tighter requirements.
	return ActionResult.success()

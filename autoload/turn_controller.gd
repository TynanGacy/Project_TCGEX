class_name TurnController
extends Node
## Singleton gateway for all game actions.
## Call request_action() to attempt any action; it validates turn ownership,
## delegates to the action's own validate(), then applies it and emits signals.

signal turn_started(turn_number: int, current_player_id: int)
signal phase_changed(phase: int)
signal action_committed(action: GameAction)
signal action_rejected(action: GameAction, reason: String)
signal log_message(text: String)

var state: GameState


func _ready() -> void:
	if state == null:
		state = GameState.new()
	_start_turn(state.current_player_id)


func set_state(gs: GameState) -> void:
	state = gs


func request_action(action: GameAction) -> void:
	if state == null:
		_emit_reject(action, "No GameState assigned.")
		return

	var gate := _gate_action(action)
	if not gate.ok:
		_emit_reject(action, gate.reason)
		return

	var res := action.validate(state)
	if not res.ok:
		_emit_reject(action, res.reason)
		return

	action.apply(state)
	action_committed.emit(action)

	if action is ActionAdvancePhase:
		phase_changed.emit(state.phase)

	if action is ActionEndTurn:
		turn_started.emit(state.turn_number, state.current_player_id)
		phase_changed.emit(state.phase)

	log_message.emit("[P%d][%s] %s" % [
		action.actor_id,
		TurnPhase.phase_to_string(state.phase),
		action.description()
	])


func next_phase(actor_id: int) -> void:
	request_action(ActionAdvancePhase.new(actor_id))


func end_turn(actor_id: int) -> void:
	request_action(ActionEndTurn.new(actor_id))


func _start_turn(player_id: int) -> void:
	state.begin_turn(player_id)
	turn_started.emit(state.turn_number, state.current_player_id)
	phase_changed.emit(state.phase)
	log_message.emit("Turn %d start: Player %d" % [state.turn_number, state.current_player_id])


func _emit_reject(action: GameAction, reason: String) -> void:
	action_rejected.emit(action, reason)
	log_message.emit("[REJECT] %s (%s)" % [action.description(), reason])


## First gate: only the current player may submit actions.
func _gate_action(action: GameAction) -> ActionResult:
	if action.actor_id != state.current_player_id:
		return ActionResult.fail("Not your turn.")
	return ActionResult.success()

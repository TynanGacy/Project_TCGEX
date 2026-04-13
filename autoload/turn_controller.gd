class_name TurnController
extends Node
## Singleton gateway for all game actions.
##
## All game mutations flow through request_action().  It validates turn
## ownership, delegates to the action's own validate(), applies it, and emits
## the appropriate signals.
##
## After an ActionAttack resolves, _resolve_post_attack() is called to handle
## knockouts, prize-taking, and win-condition checking — keeping that logic
## centralised here rather than spread across the visual layer.

## Core action signals.
signal turn_started(turn_number: int, current_player_id: int)
signal phase_changed(phase: int)
signal action_committed(action: GameAction)
signal action_rejected(action: GameAction, reason: String)
signal log_message(text: String)

## Combat outcome signals — main.gd connects to these for visual feedback.
signal pokemon_knocked_out(victim: CardInstance, scoring_player_id: int)
signal prize_taken(player_id: int, card: CardInstance)

## Emitted when an active slot becomes empty and needs a bench Pokemon.
## [player_id] is the player who must promote, not necessarily the current player.
signal active_slot_emptied(player_id: int)

## Emitted when the game ends.
signal game_over(winner_player_id: int)

## Effect-choice signals: emitted when a card effect needs a player decision.
## The UI layer should connect to these and call resolve_effect_choice() with
## the chosen CardInstance array once the player has made their selection.
##
## [reason]    — human-readable description of why a choice is needed.
## [player_id] — the player who must decide.
## [choices]   — Array[CardInstance] of legal options to pick from.
signal effect_choice_required(reason: String, player_id: int, choices: Array)

## Emitted after resolve_effect_choice() completes.
signal effect_choice_resolved(player_id: int, chosen: Array)

var state: GameState

## Pending choice context set by an effect that needs player input.
## Cleared after resolve_effect_choice() is called.
var _pending_choice: Dictionary = {}


func _ready() -> void:
	## _ready() fires immediately when the autoload is registered — before
	## main.gd calls set_state().  Create a throw-away GameState so signals
	## emitted here have a valid object to reference, even though no listeners
	## are connected yet.  set_state() replaces it with the real one.
	if state == null:
		state = GameState.new()
	# Initialise card effects that don't depend on the CardLibrary (Trainer effects).
	# AttackEffects auto-detection is deferred until set_state() where the
	# library is also available.
	CardEffectRegistry.setup()
	_start_turn(state.current_player_id)


func set_state(gs: GameState) -> void:
	state = gs


## Extended set_state that also finishes CardEffectRegistry setup with the
## CardLibrary so AttackEffects auto-detection can run.
func set_state_with_library(gs: GameState, library: CardLibrary) -> void:
	state = gs
	# Re-run setup with the library.  The guard inside setup() prevents
	# double-registration; reset the flag so AttackEffects.register_all() runs.
	CardEffectRegistry._initialized = false
	CardEffectRegistry.setup(library)


## Called by the UI layer in response to effect_choice_required.
## [chosen] is an Array[CardInstance] with the player's selection.
func resolve_effect_choice(player_id: int, chosen: Array) -> void:
	if _pending_choice.is_empty():
		return
	var callback: Callable = _pending_choice.get("callback", Callable())
	_pending_choice.clear()
	if callback.is_valid():
		callback.call(chosen)
	effect_choice_resolved.emit(player_id, chosen)


## Convenience: emit an effect_choice_required signal and store the callback
## for when the player responds.  Called by effect implementations that need
## player input.
func request_effect_choice(
		reason: String,
		player_id: int,
		choices: Array,
		callback: Callable
) -> void:
	_pending_choice = {"reason": reason, "player_id": player_id, "callback": callback}
	effect_choice_required.emit(reason, player_id, choices)


## ============================================================
## Public API
## ============================================================

func request_action(action: GameAction) -> void:
	if state == null:
		_emit_reject(action, "No GameState assigned.")
		return

	## Forced promotions bypass the turn-ownership gate so the opponent's board
	## can be fixed immediately after a knockout.
	var skip_gate := action is ActionPromoteFromBench \
		and (action as ActionPromoteFromBench).forced

	## System-generated prize actions are also exempt from the gate check.
	skip_gate = skip_gate or action is ActionTakePrize

	if not skip_gate:
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

	## Phase-transition signals.
	if action is ActionAdvancePhase:
		phase_changed.emit(state.phase)

	if action is ActionEndTurn:
		## Apply end-of-turn special conditions for the player who just ended.
		state.apply_end_of_turn_conditions(1 - state.current_player_id)
		turn_started.emit(state.turn_number, state.current_player_id)
		phase_changed.emit(state.phase)

	## Post-attack: knockouts, prizes, promotion checks, win condition.
	if action is ActionAttack:
		_resolve_post_attack(action as ActionAttack)

	log_message.emit("[P%d][%s] %s" % [
		action.actor_id,
		TurnPhase.phase_to_string(state.phase),
		action.description()
	])


func next_phase(actor_id: int) -> void:
	request_action(ActionAdvancePhase.new(actor_id))


func end_turn(actor_id: int) -> void:
	request_action(ActionEndTurn.new(actor_id))


## ============================================================
## Post-attack resolution
## ============================================================

func _resolve_post_attack(action: ActionAttack) -> void:
	## 1. Detect and discard any knocked-out opponent Pokemon.
	var opp_id := 1 - action.actor_id
	var knocked_out := state.resolve_knockouts(opp_id)

	for ko_info in knocked_out:
		var victim := ko_info["victim"] as CardInstance
		pokemon_knocked_out.emit(victim, action.actor_id)

		## 2. Auto-take one prize card for each knockout.
		var prizes_zone := state.board.get_zone("p%d_prizes" % action.actor_id)
		if not prizes_zone.is_empty():
			## Capture front() BEFORE apply() removes it — ActionTakePrize always
			## takes prizes.front() (Prize 1 = visual top of the stack), so the
			## signal must reference that same card for the visual layer to show
			## the correct card face in the hand.
			var prize_card := prizes_zone.front() as CardInstance
			var take := ActionTakePrize.new(action.actor_id)
			take.apply(state)  ## validate() not needed — system-only path.
			prize_taken.emit(action.actor_id, prize_card)

	## 3. Check whether any opponent active slot is now empty.
	var needs_promotion := false
	for slot_idx in range(state.board.num_active_slots):
		if state.board.get_active_card(opp_id, slot_idx) == null \
				and not state.board.get_bench_cards(opp_id).is_empty():
			needs_promotion = true
			break

	if needs_promotion:
		## Emit the signal — handlers may resolve the promotion synchronously
		## (CPU auto-promotes) or asynchronously (human dialog).
		active_slot_emptied.emit(opp_id)

		## Re-check: if a synchronous handler (e.g. CPU) already filled the slot,
		## we can proceed without waiting.
		needs_promotion = false
		for slot_idx in range(state.board.num_active_slots):
			if state.board.get_active_card(opp_id, slot_idx) == null \
					and not state.board.get_bench_cards(opp_id).is_empty():
				needs_promotion = true
				break

	## 4. Check win conditions.
	var winner := state.check_win_condition()
	if winner >= 0:
		game_over.emit(winner)
		return

	## 5. Auto-advance to END phase.  Skip if a human promotion dialog is still
	##    open — main.gd will call next_phase() after the player chooses.
	if not needs_promotion and state.phase == TurnPhase.Phase.ATTACK:
		next_phase(action.actor_id)


## ============================================================
## Turn start
## ============================================================

func _start_turn(player_id: int) -> void:
	state.begin_turn(player_id)
	turn_started.emit(state.turn_number, state.current_player_id)
	phase_changed.emit(state.phase)
	log_message.emit("Turn %d — Player %d's turn" % [state.turn_number, state.current_player_id])


## ============================================================
## Gate and reject helpers
## ============================================================

func _gate_action(action: GameAction) -> ActionResult:
	## Only the current player may submit actions.
	if action.actor_id != state.current_player_id:
		return ActionResult.fail("Not your turn.")
	return ActionResult.success()


func _emit_reject(action: GameAction, reason: String) -> void:
	action_rejected.emit(action, reason)
	log_message.emit("[REJECT] %s — %s" % [action.description(), reason])

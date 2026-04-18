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

## Emitted when one or more coin flips need to be shown (after action resolves).
## batch: Array[Dictionary{results: Array[bool], reason: String}]
signal coin_flip_batch_ready(batch: Array)

## Emitted when a card search/retrieve effect needs player input.
## pile:            Array[CardInstance] already filtered to valid choices.
## max_count:       how many cards the player may select.
## reason:          human-readable description.
## preceding_flips: any pending coin-flip results to show first.
## actor_id:        the player making the choice.
signal card_search_requested(pile: Array, max_count: int, reason: String, preceding_flips: Array, actor_id: int)

## Emitted when the player must choose which energy to pay for a retreat.
## energies:     Array[CardInstance] currently attached to the retreating Pokemon.
## count:        exact number to discard.
## pokemon_name: for display.
signal energy_discard_choice_requested(energies: Array, count: int, pokemon_name: String)

var state: GameState

## Pending choice context set by an effect that needs player input.
## Cleared after resolve_effect_choice() is called.
var _pending_choice: Dictionary = {}

## Coin-flip results queued for display (flushed after the outermost
## request_action() call completes so nested calls don't fire prematurely).
var _pending_flip_display: Array[Dictionary] = []

## Stored callbacks for card-search and energy-discard interactions.
var _pending_search_callback: Callable
var _pending_energy_discard_callback: Callable

## Nesting depth of request_action() calls.  Coin-flip display is only
## flushed when the depth returns to zero (outermost call).
var _request_depth: int = 0


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


## ============================================================
## Coin-flip helpers
## ============================================================

## Rolls [count] coins, queues the results for display, and returns them.
## true = heads, false = tails.  Call this instead of randi() % 2 so the
## visual layer can show an animated coin-flip overlay.
func flip_coins(count: int, reason: String) -> Array[bool]:
	var results: Array[bool] = []
	for _i in count:
		results.append(randi() % 2 == 1)
	_pending_flip_display.append({"results": results, "reason": reason})
	return results


## Records a pre-computed set of results (used by flip-until-tails patterns
## where the caller accumulates individual randi() rolls).
func record_flip_results(results: Array[bool], reason: String) -> void:
	_pending_flip_display.append({"results": results, "reason": reason})


## ============================================================
## Card-search helpers
## ============================================================

## Requests a card-search interaction from the UI layer.
## [pile] must already be filtered to eligible cards.
## Any pending coin-flip results are forwarded so the UI can show them
## before the search popup.
func request_card_search(
		pile: Array,
		max_count: int,
		reason: String,
		callback: Callable
) -> void:
	_pending_search_callback = callback
	var flips := _pending_flip_display.duplicate(true)
	_pending_flip_display.clear()
	var actor_id := state.current_player_id if state else 0
	card_search_requested.emit(pile, max_count, reason, flips, actor_id)


## Called by the UI layer when the player confirms their card selection.
func resolve_card_search(chosen: Array) -> void:
	var cb := _pending_search_callback
	_pending_search_callback = Callable()
	if cb.is_valid():
		cb.call(chosen)


## ============================================================
## Energy-discard helpers
## ============================================================

## Requests a choice of which attached energy to pay for retreat.
func request_energy_discard_choice(
		energies: Array,
		count: int,
		pokemon_name: String,
		callback: Callable
) -> void:
	_pending_energy_discard_callback = callback
	energy_discard_choice_requested.emit(energies, count, pokemon_name)


## Called by the UI layer when the player confirms their energy selection.
func resolve_energy_discard_choice(chosen: Array) -> void:
	var cb := _pending_energy_discard_callback
	_pending_energy_discard_callback = Callable()
	if cb.is_valid():
		cb.call(chosen)


## ============================================================
## Internal flush
## ============================================================

func _flush_pending_flips() -> void:
	if _pending_flip_display.is_empty():
		return
	var batch := _pending_flip_display.duplicate(true)
	_pending_flip_display.clear()
	coin_flip_batch_ready.emit(batch)


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
	_request_depth += 1

	if state == null:
		_emit_reject(action, "No GameState assigned.")
		_request_depth -= 1
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
			_request_depth -= 1
			return

	var res := action.validate(state)
	if not res.ok:
		_emit_reject(action, res.reason)
		_request_depth -= 1
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

	_request_depth -= 1
	if _request_depth == 0:
		_flush_pending_flips()


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
	##    Attacks happen from MAIN; one advance step reaches END (ATTACK phase
	##    is no longer part of the normal flow).
	if not needs_promotion:
		if state.phase == TurnPhase.Phase.MAIN:
			next_phase(action.actor_id)   ## MAIN -> END


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

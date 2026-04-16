class_name CpuPlayer
extends Node
## Simple autonomous CPU opponent — always plays as Player 1.
##
## Decision priority on each turn (proof-of-concept level):
##   1. Ensure an active Pokemon exists (promote or play Basic from hand).
##   2. Fill the bench with any remaining Basic Pokemon from hand.
##   3. Evolve any in-play Pokemon if a valid evolution card is in hand.
##   4. Attach one energy to the primary active Pokemon.
##   5. Advance to ATTACK phase and use the first affordable attack.
##   6. Advance to END phase and end the turn.
##
## The CPU runs async so each action is visually separated by a short pause,
## making it easier for the human player to follow what's happening.

const THINK_DELAY  := 0.6   ## Pause between individual actions (seconds).
const ATTACK_DELAY := 1.0   ## Longer pause before attacking.

var _state: GameState
var _tc: TurnController
var _player_id: int = 1
var _running: bool = false


## Called once by main.gd after game_state and turn_controller are ready.
func setup(state: GameState, turn_controller: TurnController) -> void:
	_state = state
	_tc    = turn_controller
	if not _tc.turn_started.is_connected(_on_turn_started):
		_tc.turn_started.connect(_on_turn_started)

func _exit_tree() -> void:
	## Defensive disconnect: avoids keeping stale callables around if a CPU node
	## is replaced/recreated while the TurnController singleton remains alive.
	if _tc != null and _tc.turn_started.is_connected(_on_turn_started):
		_tc.turn_started.disconnect(_on_turn_started)


func _on_turn_started(_turn_number: int, current_player_id: int) -> void:
	if current_player_id != _player_id:
		return
	## Defer one frame so visual turn-start effects settle before the AI moves.
	_run_turn.call_deferred()


## ============================================================
## Main turn loop
## ============================================================

func _run_turn() -> void:
	if _running:
		return
	_running = true

	await get_tree().create_timer(THINK_DELAY).timeout

	## START phase is auto-advanced to MAIN by the phase_changed handler,
	## so we begin directly in MAIN.

	## ── MAIN PHASE ──────────────────────────────────────────────────────────

	_play_basic_to_active_if_needed()
	await get_tree().create_timer(THINK_DELAY).timeout

	_fill_bench()
	await get_tree().create_timer(THINK_DELAY).timeout

	_try_evolve()
	await get_tree().create_timer(THINK_DELAY).timeout

	_try_attach_energy()
	await get_tree().create_timer(ATTACK_DELAY).timeout

	## Attack from MAIN phase.  If the attack succeeds, _resolve_post_attack
	## auto-advances to END (which auto-ends the turn via phase_changed).
	_try_attack()
	await get_tree().create_timer(THINK_DELAY).timeout

	## If the turn hasn't already ended (no attack was made or it was
	## rejected), advance to END manually — the auto-end-turn handler in
	## main.gd will finish the turn.
	if _state.current_player_id == _player_id:
		_advance_phase()   ## MAIN -> END (auto-ends turn)

	_running = false


## ============================================================
## Forced promotion (called externally by main.gd when a KO empties an
## active slot that belongs to the CPU)
## ============================================================

func handle_promotion_needed() -> void:
	## Automatically promotes a random bench Pokemon (forced — bypasses turn gate).
	var bench := _state.board.get_bench_cards(_player_id)
	if bench.is_empty():
		return  ## No bench Pokemon — game-over is handled elsewhere.

	var bench_index := randi() % bench.size()
	_tc.request_action(
		ActionPromoteFromBench.new(_player_id, _player_id, bench_index, true)
	)


## ============================================================
## Individual action helpers
## ============================================================

func _advance_phase() -> void:
	_tc.next_phase(_player_id)


func _play_basic_to_active_if_needed() -> void:
	## If every active slot is empty, play the first Basic Pokemon from hand.
	if _state.board.count_active_pokemon(_player_id) > 0:
		return

	var basic := _find_basic_in_hand()
	if basic == null:
		return

	## Playing to "active" will fill the first open slot.
	_tc.request_action(ActionPlayBasicPokemon.new(_player_id, basic, "active"))


func _fill_bench() -> void:
	## Keep playing Basic Pokemon to the bench while space and hand cards allow.
	## Guard with an iteration cap to prevent infinite loops.
	var bench_zone := "p%d_bench" % _player_id
	var max_iter := 8

	for _i in max_iter:
		if not _state.board.can_add_to_zone(bench_zone):
			break
		var hand_before := _state.board.get_hand_cards(_player_id).size()
		var basic := _find_basic_in_hand()
		if basic == null:
			break
		_tc.request_action(ActionPlayBasicPokemon.new(_player_id, basic, "bench"))
		## If hand size didn't shrink the action failed (shouldn't happen).
		if _state.board.get_hand_cards(_player_id).size() >= hand_before:
			break


func _try_evolve() -> void:
	## Evolve at most one Pokemon per turn call (keeps it simple).
	for card in _state.board.get_hand_cards(_player_id):
		if not (card.data is PokemonCardData):
			continue
		var pdata := card.data as PokemonCardData
		if pdata.stage == PokemonCardData.Stage.BASIC:
			continue  ## Not an evolution card.

		var target := _find_evolution_target(pdata)
		if target == null:
			continue

		_tc.request_action(ActionEvolvePokemon.new(_player_id, card, target))
		return  ## One evolution per call.


func _try_attach_energy() -> void:
	var player := _state.get_player(_player_id)
	if player == null or not player.can_attach_energy():
		return

	var energy := _find_energy_in_hand()
	if energy == null:
		return

	## Prefer attaching to an active Pokemon; fall back to bench if active is
	## empty (this can happen on the very first turn of the CPU).
	var target := _best_energy_target()
	if target == null:
		return

	_tc.request_action(ActionAttachEnergy.new(_player_id, energy, target))


func _try_attack() -> void:
	## Scan active slots in order; use the first affordable attack found.
	var opp_id := 1 - _player_id

	for slot_idx in range(_state.board.num_active_slots):
		var attacker := _state.board.get_active_card(_player_id, slot_idx)
		if attacker == null or not (attacker.data is PokemonCardData):
			continue

		var defender := _find_first_opponent_active(opp_id)
		if defender == null:
			continue

		var pdata := attacker.data as PokemonCardData
		for atk_idx in range(pdata.attacks.size()):
			if AttackResolver.can_afford(attacker, pdata.attacks[atk_idx]):
				_tc.request_action(
					ActionAttack.new(_player_id, slot_idx, defender, atk_idx)
				)
				return  ## One attack per turn.


## ============================================================
## Finders
## ============================================================

func _find_basic_in_hand() -> CardInstance:
	for card in _state.board.get_hand_cards(_player_id):
		if card.data is PokemonCardData \
				and (card.data as PokemonCardData).stage == PokemonCardData.Stage.BASIC:
			return card
	return null


func _find_energy_in_hand() -> CardInstance:
	for card in _state.board.get_hand_cards(_player_id):
		if card.data is EnergyCardData:
			return card
	return null


func _best_energy_target() -> CardInstance:
	## Primary active slot first, then first bench Pokemon.
	for slot_idx in range(_state.board.num_active_slots):
		var active := _state.board.get_active_card(_player_id, slot_idx)
		if active != null:
			return active
	var bench := _state.board.get_bench_cards(_player_id)
	return bench[0] if not bench.is_empty() else null


func _find_first_opponent_active(opp_id: int) -> CardInstance:
	for slot_idx in range(_state.board.num_active_slots):
		var opp := _state.board.get_active_card(opp_id, slot_idx)
		if opp != null:
			return opp
	return null


func _find_evolution_target(pdata: PokemonCardData) -> CardInstance:
	## Returns the first in-play Pokemon that [pdata] can evolve from.
	for slot_idx in range(_state.board.num_active_slots):
		var active := _state.board.get_active_card(_player_id, slot_idx)
		if _is_valid_evo_target(active, pdata):
			return active
	for bench_card in _state.board.get_bench_cards(_player_id):
		if _is_valid_evo_target(bench_card, pdata):
			return bench_card
	return null


func _is_valid_evo_target(target: CardInstance, evo_data: PokemonCardData) -> bool:
	if target == null or not (target.data is PokemonCardData):
		return false
	## Cannot evolve a Pokemon on the same turn it was played.
	if target.turn_entered_play >= _state.turn_number:
		return false
	return (target.data as PokemonCardData).name_slug == evo_data.evolves_from

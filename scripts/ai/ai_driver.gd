class_name AIDriver
extends Node
## Drives the CPU side of a match.  Listens to the manager's turn / prize /
## promotion / discard / query signals and submits actions or resolves
## responses on behalf of the CPU player.
##
## Phase A: priority-ordered heuristics via OpponentAI; "first valid option"
## fallback for every dialog/query so the match never blocks waiting for
## human input on the CPU side.
##
## Owned by Match (instantiated in match.gd when opponent_is_cpu is true).

const TURN_ACTION_BUDGET: int = 25

var _main: Node = null
var cpu_pid: int = 1
var _ai: OpponentAI = null
var _profile: AIProfile = null
var _driving: bool = false


func init(main_node: Node, deck_id: String = "") -> void:
	_main = main_node
	_ai = OpponentAI.new()
	_profile = AIProfile.for_deck(deck_id)

	var mgr = _main.manager
	mgr.turn_started.connect(_on_turn_started)
	mgr.prize_selection_required.connect(_on_prize_selection_required)
	mgr.promotion_required.connect(_on_promotion_required)
	mgr.energy_discard_choice_required.connect(_on_energy_discard_required)
	mgr.retreat_energy_choice_required.connect(_on_retreat_energy_required)
	if mgr.trainer_resolver != null:
		mgr.trainer_resolver.player_query_requested.connect(_on_trainer_query)
	if mgr.attack_resolver != null:
		mgr.attack_resolver.player_query_requested.connect(_on_attack_query)


## --- Setup placement -------------------------------------------------------
## Called by SetupManager when the CPU's placement window opens.  Places one
## basic active + up to OpponentAI.MAX_BENCH_FILL basics on the bench.  Returns
## synchronously once placement is legal so the setup loop can advance.

func auto_place_setup(pid: int) -> void:
	var mgr = _main.manager
	## Active first.
	for i in range(1, mgr.active_slot_count + 1):
		var slot := "p%d_active%d" % [pid, i]
		if mgr.board_position.get_instance(slot) != null:
			continue
		var basic: PokemonCardData = _first_basic_in_hand(pid)
		if basic == null:
			return  ## No basics — shouldn't happen post-mulligan, but bail safely.
		_main._authority.request_action(ActionSetupPlayBasic.new(pid, basic, slot))
		break

	## Up to MAX_BENCH_FILL bench.
	var placed: int = 0
	for i in range(1, mgr.bench_slot_count + 1):
		if placed >= OpponentAI.MAX_BENCH_FILL:
			break
		var slot := "p%d_bench%d" % [pid, i]
		if mgr.board_position.get_instance(slot) != null:
			placed += 1
			continue
		var basic: PokemonCardData = _first_basic_in_hand(pid)
		if basic == null:
			break
		var result := _main._authority.request_action(
				ActionSetupPlayBasic.new(pid, basic, slot))
		if result.ok:
			placed += 1


## --- Turn driver -----------------------------------------------------------

func _on_turn_started(pid: int, _turn_number: int) -> void:
	if pid != cpu_pid:
		return
	if _driving:
		return  ## Re-entrancy guard.
	_drive_turn_async()


func _drive_turn_async() -> void:
	_driving = true
	var mgr = _main.manager
	var budget: int = TURN_ACTION_BUDGET

	## Wait one frame so the turn-start sequence (draw, signal cascade) settles
	## before we start submitting actions.
	await _main.get_tree().process_frame

	while budget > 0:
		budget -= 1
		if mgr.current_phase != ManagerSystem.Phase.MAIN or mgr.current_player != cpu_pid:
			break  ## Turn ended out from under us (e.g. KO mid-attack ended game).
		if mgr.prize_selection_phase_for >= 0 or mgr.promotion_phase_for >= 0:
			## Paused for prize/promotion; the signal handlers will advance.
			await _main.get_tree().process_frame
			continue
		var action: GameAction = _ai.decide_action(mgr, cpu_pid)
		if action == null:
			break
		var result = await _main._authority.request_action_async(action)
		if result == null or not result.ok:
			break  ## Fallback: end turn rather than thrash on invalid actions.

	## End turn — only if we're still the active player in main phase.
	if mgr.current_phase == ManagerSystem.Phase.MAIN and mgr.current_player == cpu_pid:
		mgr.end_turn()
	_driving = false


## --- Prize / promotion fallbacks -------------------------------------------

func _on_prize_selection_required(pid: int) -> void:
	if pid != cpu_pid:
		return
	var mgr = _main.manager
	var prizes: Array = mgr.game_position.prizes[pid] as Array
	for i in prizes.size():
		if prizes[i] != null:
			_main._authority.request_action(ActionTakePrize.new(pid, i))
			return


func _on_promotion_required(pid: int) -> void:
	if pid != cpu_pid:
		return
	var mgr = _main.manager
	var bench_slot: String = ""
	for i in range(1, mgr.bench_slot_count + 1):
		var slot := "p%d_bench%d" % [pid, i]
		if mgr.board_position.get_instance(slot) != null:
			bench_slot = slot
			break
	if bench_slot.is_empty():
		return  ## No bench — game is about to end via _check_game_won.
	var active_slot: String = ""
	for i in range(1, mgr.active_slot_count + 1):
		var slot := "p%d_active%d" % [pid, i]
		if mgr.board_position.get_instance(slot) == null:
			active_slot = slot
			break
	if active_slot.is_empty():
		return
	_main._authority.request_action(ActionPromote.new(pid, bench_slot, active_slot))


## --- Energy / retreat discard fallbacks ------------------------------------

func _on_energy_discard_required(pid: int, eligible: Array, count: int, _slot: String) -> void:
	if pid != cpu_pid:
		return
	var indices: Array[int] = []
	var take: int = mini(count, eligible.size())
	for i in take:
		indices.append(i)
	_main.manager.resolve_energy_discard_choice(indices)


func _on_retreat_energy_required(pid: int, eligible: Array, count: int, _slot: String) -> void:
	if pid != cpu_pid:
		return
	var indices: Array[int] = []
	var take: int = mini(count, eligible.size())
	for i in take:
		indices.append(i)
	_main.manager.resolve_retreat_energy_choice(indices)


## --- Trainer / attack query fallbacks --------------------------------------
## Every query type gets a "first valid option" or "no" response so the
## pipeline never hangs on the CPU side.

func _on_trainer_query(query) -> void:
	if query == null or query.player_id != cpu_pid:
		return
	var resolver = _main.manager.trainer_resolver
	if resolver == null:
		return
	resolver.resolve_query(_default_trainer_response(query))


func _default_trainer_response(query) -> Variant:
	match query.kind:
		TrainerQuery.Kind.GENERIC_CHOICE:
			return query.options[0] if not query.options.is_empty() else ""
		TrainerQuery.Kind.CHOOSE_OWN_POKEMON, \
		TrainerQuery.Kind.CHOOSE_OPPONENT_BENCH, \
		TrainerQuery.Kind.CHOOSE_OPPONENT_POKEMON, \
		TrainerQuery.Kind.CHOOSE_OWN_BENCH:
			return query.options[0] if not query.options.is_empty() else ""
		TrainerQuery.Kind.CHOOSE_ENERGY_ON_POKEMON:
			return query.options[0] if not query.options.is_empty() else null
		TrainerQuery.Kind.CHOOSE_FROM_HAND, \
		TrainerQuery.Kind.CHOOSE_FROM_LIST, \
		TrainerQuery.Kind.REORDER_TOP_OF_DECK:
			var take_n: int = clampi(query.min_selections, 0, query.options.size())
			var arr: Array = []
			for i in take_n:
				arr.append(query.options[i])
			return arr
	return null


func _on_attack_query(query) -> void:
	if query == null or query.player_id != cpu_pid:
		return
	var resolver = _main.manager.attack_resolver
	if resolver == null:
		return
	resolver.resolve_query(_default_attack_response(query))


func _default_attack_response(query) -> Variant:
	match query.kind:
		AttackQuery.Kind.MAY_ABILITY, \
		AttackQuery.Kind.MAY_DISCARD_FOR_BONUS, \
		AttackQuery.Kind.MAY_CONFIRM:
			return false  ## Conservative: don't opt in.
		AttackQuery.Kind.CHOOSE_BENCH_TARGET, \
		AttackQuery.Kind.CHOOSE_ENERGY_TYPE, \
		AttackQuery.Kind.GENERIC_CHOICE:
			return query.options[0] if not query.options.is_empty() else ""
		AttackQuery.Kind.CHOOSE_ENERGY_DISCARD, \
		AttackQuery.Kind.CHOOSE_ENERGY_FROM_HAND, \
		AttackQuery.Kind.CHOOSE_DISCARD_COUNT:
			var take_n: int = clampi(query.min_selections, 0, query.options.size())
			var arr: Array = []
			for i in take_n:
				arr.append(query.options[i])
			return arr
		AttackQuery.Kind.CHOOSE_OPP_HAND_BLIND:
			var n: int = clampi(query.min_selections, 0, query.options.size())
			var arr: Array = []
			for i in n:
				arr.append(i)
			return arr
		AttackQuery.Kind.CHOOSE_OPP_HAND_OPEN:
			var n: int = clampi(query.min_selections, 0, query.options.size())
			var arr: Array = []
			for i in n:
				arr.append(query.options[i])
			return arr
		AttackQuery.Kind.CHOOSE_ATTACK_FROM_CARDS:
			return query.options[0] if not query.options.is_empty() else null
		AttackQuery.Kind.CHOOSE_ORDER:
			return query.options.duplicate()
	return null


## --- helpers ---------------------------------------------------------------

func _first_basic_in_hand(pid: int) -> PokemonCardData:
	for card: CardData in _main.manager.game_position.hands[pid] as Array:
		if card is PokemonCardData \
				and (card as PokemonCardData).stage == PokemonCardData.Stage.BASIC:
			return card
	return null

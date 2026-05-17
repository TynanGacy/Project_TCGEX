class_name OpponentAI
extends RefCounted
## Heuristic CPU opponent.  Decides one main-phase action at a time by
## enumerating candidate actions, filtering to those that pass validate(),
## and picking by priority (active first, then bench, energy, attack).
##
## Phase A scope: priority-ordered heuristics; no trainer/item play, no
## evolution, no ability use, no retreat.  Phase B will add scoring +
## the missing action types.
##
## Every public method returns null on failure (no legal action) rather
## than raising; the driver treats null as "end turn".

const MAX_BENCH_FILL: int = 3


## Returns the next action the CPU should take, or null if it should end the
## turn.  Caller is responsible for actually submitting via request_action.
func decide_action(manager, pid: int) -> GameAction:
	if manager == null:
		return null
	if not manager.is_main_phase_for(pid):
		return null

	## 1. No active Pokémon — must play one.  This is rare mid-game (engine
	##    auto-promotes on KO when there's a unique option) but guard for it.
	var active_action: GameAction = _try_play_basic_to_first_empty_active(manager, pid)
	if active_action != null:
		return active_action

	## 2. Fill bench up to MAX_BENCH_FILL with basics from hand.
	var bench_action: GameAction = _try_play_basic_to_bench(manager, pid)
	if bench_action != null:
		return bench_action

	## 3. Attach one energy (once per turn) — prefer the active's needed type.
	if not manager.energy_attached_this_turn[pid]:
		var energy_action: GameAction = _try_attach_energy(manager, pid)
		if energy_action != null:
			return energy_action

	## 4. Attack if any of the active's attacks is fully paid + legal.
	if not manager.attack_used_this_turn[pid]:
		var attack_action: GameAction = _try_attack(manager, pid)
		if attack_action != null:
			return attack_action

	## 5. Nothing useful to do — fall through to end turn.
	return null


## --- 1. Place first basic into the empty active slot -------------------------

func _try_play_basic_to_first_empty_active(manager, pid: int) -> GameAction:
	for i in range(1, manager.active_slot_count + 1):
		var slot := "p%d_active%d" % [pid, i]
		if manager.board_position.get_instance(slot) != null:
			continue
		var basic: PokemonCardData = _first_basic_in_hand(manager, pid)
		if basic == null:
			return null
		var action := ActionPlayPokemon.new(pid, basic, slot)
		if action.validate(manager).ok:
			return action
	return null


## --- 2. Fill bench up to MAX_BENCH_FILL --------------------------------------

func _try_play_basic_to_bench(manager, pid: int) -> GameAction:
	var bench_filled: int = 0
	for i in range(1, manager.bench_slot_count + 1):
		var slot := "p%d_bench%d" % [pid, i]
		if manager.board_position.get_instance(slot) != null:
			bench_filled += 1
	if bench_filled >= MAX_BENCH_FILL:
		return null

	var basic: PokemonCardData = _first_basic_in_hand(manager, pid)
	if basic == null:
		return null
	for i in range(1, manager.bench_slot_count + 1):
		var slot := "p%d_bench%d" % [pid, i]
		if manager.board_position.get_instance(slot) != null:
			continue
		var action := ActionPlayPokemon.new(pid, basic, slot)
		if action.validate(manager).ok:
			return action
	return null


## --- 3. Attach one energy (prefer typed match) -------------------------------

func _try_attach_energy(manager, pid: int) -> GameAction:
	var energies: Array[EnergyCardData] = _energies_in_hand(manager, pid)
	if energies.is_empty():
		return null

	## Prefer to attach to the active so it can attack.  Fall back to first
	## bench slot with a Pokémon.
	var targets: Array[String] = []
	for i in range(1, manager.active_slot_count + 1):
		targets.append("p%d_active%d" % [pid, i])
	for i in range(1, manager.bench_slot_count + 1):
		targets.append("p%d_bench%d" % [pid, i])

	for slot: String in targets:
		var inst: PokemonInstance = manager.board_position.get_instance(slot)
		if inst == null:
			continue
		var preferred: EnergyCardData = _pick_best_energy_for(energies, inst)
		if preferred == null:
			preferred = energies[0]
		var action := ActionAttachEnergy.new(pid, preferred, slot)
		if action.validate(manager).ok:
			return action
	return null


## --- 4. Attack with highest base damage attack that's affordable + legal -----

func _try_attack(manager, pid: int) -> GameAction:
	var best: ActionAttack = null
	var best_damage: int = -1
	for i in range(1, manager.active_slot_count + 1):
		var atk_slot := "p%d_active%d" % [pid, i]
		var attacker: PokemonInstance = manager.board_position.get_instance(atk_slot)
		if attacker == null or attacker.card == null:
			continue
		var opp_id: int = 1 - pid
		var tgt_slot: String = _first_opponent_active(manager, opp_id)
		if tgt_slot == "":
			continue
		for atk_idx in attacker.card.attacks.size():
			var action := ActionAttack.new(pid, atk_slot, atk_idx, tgt_slot)
			if not action.validate(manager).ok:
				continue
			var dmg: int = int(attacker.card.attacks[atk_idx].base_damage)
			if dmg > best_damage:
				best_damage = dmg
				best = action
	return best


## --- helpers -----------------------------------------------------------------

func _first_basic_in_hand(manager, pid: int) -> PokemonCardData:
	for card: CardData in manager.game_position.hands[pid] as Array:
		if card is PokemonCardData \
				and (card as PokemonCardData).stage == PokemonCardData.Stage.BASIC:
			return card
	return null


func _energies_in_hand(manager, pid: int) -> Array[EnergyCardData]:
	var out: Array[EnergyCardData] = []
	for card: CardData in manager.game_position.hands[pid] as Array:
		if card is EnergyCardData:
			out.append(card)
	return out


## Picks an energy whose type matches one of [inst]'s attack costs, otherwise
## returns null so the caller can fall back to the first available energy.
func _pick_best_energy_for(energies: Array[EnergyCardData], inst: PokemonInstance) -> EnergyCardData:
	if inst == null or inst.card == null:
		return null
	var needed_types: Dictionary = {}
	for atk: AttackData in inst.card.attacks:
		if atk.cost_fire > 0:      needed_types[PokemonCardData.EnergyType.FIRE]      = true
		if atk.cost_water > 0:     needed_types[PokemonCardData.EnergyType.WATER]     = true
		if atk.cost_grass > 0:     needed_types[PokemonCardData.EnergyType.GRASS]     = true
		if atk.cost_lightning > 0: needed_types[PokemonCardData.EnergyType.LIGHTNING] = true
		if atk.cost_psychic > 0:   needed_types[PokemonCardData.EnergyType.PSYCHIC]   = true
		if atk.cost_fighting > 0:  needed_types[PokemonCardData.EnergyType.FIGHTING]  = true
		if atk.cost_darkness > 0:  needed_types[PokemonCardData.EnergyType.DARKNESS]  = true
		if atk.cost_metal > 0:     needed_types[PokemonCardData.EnergyType.METAL]     = true
	for e: EnergyCardData in energies:
		if needed_types.has(e.energy_type):
			return e
	return null


func _first_opponent_active(manager, opp_id: int) -> String:
	for i in range(1, manager.active_slot_count + 1):
		var slot := "p%d_active%d" % [opp_id, i]
		if manager.board_position.get_instance(slot) != null:
			return slot
	return ""

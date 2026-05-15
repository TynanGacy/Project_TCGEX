extends GutTest
## GUT test suite for Tier-3 Wave 17 (Medium attacks):
##   - DR_100 Charizard Flame Pillar         (may discard + bench pick)
##   - DR_31 Grovyle Fury Cutter             (4-coin branched bonus)
##   - DR_32 Gyarados Dragon Crush           (coin-gated hits_each + discard each)
##   - DR_95 Magcargo ex Lava Flow           (variable basic-energy discard)
##   - DR_97 Rayquaza ex Dragon Burst        (type-choice discard-all)
##   - SS_68 Marill Double Bubble            (coin_multiply_damage + any-heads PAR)
##   - DR_18 Ninjask Quick Touch             (may-switch + move energy)

var _lib: CardLibrary
var _handlers_node: Node = null


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")
	_handlers_node = load("res://scenes/match/effect_handlers.gd").new()
	add_child(_handlers_node)


func after_all() -> void:
	if _handlers_node != null:
		_handlers_node.queue_free()
		_handlers_node = null


func _make_builder() -> TestBoardBuilder:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	return TestBoardBuilder.new(mgr, _lib)


## Reuses _set_attack semantics from test_tier3_attacks.gd: synthesise a
## zero-cost attack with the given key/params on the attacker's first slot.
func _set_attack(att: PokemonInstance, base_damage: int, key: String,
		params: Dictionary, chain: Array = []) -> void:
	var a: AttackData = att.card.attacks[0]
	a.base_damage = base_damage
	a.effect_key = key
	a.effect_params = params
	a.effect_chain = chain
	a.cost_colorless = 0; a.cost_fire = 0; a.cost_water = 0; a.cost_grass = 0
	a.cost_lightning = 0; a.cost_psychic = 0; a.cost_fighting = 0
	a.cost_darkness = 0; a.cost_metal = 0


## Pre-bakes a FIFO of responses. Each player_query_requested fires the next
## response via call_deferred (so the awaiting handler is registered first).
func _auto_answer_queries(mgr: ManagerSystem, values: Array) -> void:
	var queue: Array = values.duplicate()
	mgr.attack_resolver.player_query_requested.connect(
		func(_q: AttackQuery) -> void:
			if queue.is_empty():
				push_warning("Test: query fired but no canned response left")
				return
			var v: Variant = queue.pop_front()
			mgr.attack_resolver.resolve_query.call_deferred(v)
	)


## ── Flame Pillar (DR_100 Charizard) ────────────────────────────────────────

## (a) Discard yes + opp bench occupied → 60 active + 30 bench (no W/R).
func test_flame_pillar_discard_and_bench() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_100_charizard",
		{"energy": ["RS_108_fire_energy", "RS_108_fire_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	var bn := b.place_bench(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 60, "flame_pillar", {})
	_auto_answer_queries(mgr, [true, "p1_bench1"])
	var hp_tgt_before := tgt.current_hp
	var hp_bn_before := bn.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var tgt2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var bn2: PokemonInstance = mgr.board_position.get_instance("p1_bench1")
	# Charizard is Fire vs Golem (Fighting, weakness Water): no W/R boost.
	assert_eq(hp_tgt_before - tgt2.current_hp, 60, "active takes base 60")
	assert_eq(hp_bn_before - bn2.current_hp, 30, "bench takes 30 (no W/R)")
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(att2.attached_energy.size(), 1, "1 Fire energy discarded")


## (b) Discard declined → 60 active only, no bench damage.
func test_flame_pillar_decline_no_bench_damage() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_100_charizard",
		{"energy": ["RS_108_fire_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	var bn := b.place_bench(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 60, "flame_pillar", {})
	_auto_answer_queries(mgr, [false])  # decline
	var hp_tgt_before := tgt.current_hp
	var hp_bn_before := bn.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_tgt_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 60,
		"active takes base 60")
	assert_eq(hp_bn_before - (mgr.board_position.get_instance("p1_bench1") as PokemonInstance).current_hp, 0,
		"no bench damage")
	assert_eq((mgr.board_position.get_instance("p0_active1") as PokemonInstance).attached_energy.size(), 1,
		"no energy discarded")


## (c) Discard yes but opp has no bench → handler exits before any query.
func test_flame_pillar_no_opp_bench_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_100_charizard",
		{"energy": ["RS_108_fire_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 60, "flame_pillar", {})
	# No queries should fire.
	var any_query := [false]
	mgr.attack_resolver.player_query_requested.connect(
		func(_q: AttackQuery) -> void: any_query[0] = true)
	var hp_tgt_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_tgt_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 60,
		"active still takes base 60")
	assert_false(any_query[0], "no queries when opp bench is empty")
	assert_eq((mgr.board_position.get_instance("p0_active1") as PokemonInstance).attached_energy.size(), 1,
		"no energy discarded — handler short-circuits before discard")


## ── Fury Cutter (DR_31 Grovyle) ────────────────────────────────────────────

## (a) 4 heads → 10 + 60 = 70.
func test_fury_cutter_all_heads() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true, true, true, true])
	_set_attack(att, 10, "coin_flips_branch_bonus",
		{"coin_count": 4, "per_head": 10, "all_heads_bonus": 60})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 70,
		"4 heads → 10 + 60 = 70")


## (b) 2 heads → 10 + 20 = 30.
func test_fury_cutter_partial_heads() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true, true, false, false])
	_set_attack(att, 10, "coin_flips_branch_bonus",
		{"coin_count": 4, "per_head": 10, "all_heads_bonus": 60})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 30,
		"2 heads → 10 + 2×10 = 30")


## (c) 0 heads → 10 base only.
func test_fury_cutter_zero_heads() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([false, false, false, false])
	_set_attack(att, 10, "coin_flips_branch_bonus",
		{"coin_count": 4, "per_head": 10, "all_heads_bonus": 60})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 10,
		"0 heads → 10 base only")


## ── Dragon Crush (DR_32 Gyarados) ──────────────────────────────────────────

## (a) heads → 10 to active defender + 1 energy discarded from defender.
func test_dragon_crush_heads_discards_active_energy() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem",
		{"hp": 120, "energy": ["RS_106_water_energy"]})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true])
	_set_attack(att, 0, "gyarados_dragon_crush",
		{"per_target_damage": 10, "energy_discard_count": 1})
	# hits_each_defending only matters if 2-active mode; for 1-active just hits active1.
	att.card.attacks[0].hits_each_defending = true
	var hp_before := tgt.current_hp
	var energy_before := tgt.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# Golem weakness is WATER; Bagon is COLORLESS — no W/R applies, 10 dmg.
	var tgt2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - tgt2.current_hp, 10, "10 dmg to defender")
	assert_eq(tgt2.attached_energy.size(), energy_before - 1, "1 energy discarded from defender")


## (b) tails → no damage, no discard.
func test_dragon_crush_tails_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem",
		{"hp": 120, "energy": ["RS_106_water_energy"]})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([false])
	_set_attack(att, 0, "gyarados_dragon_crush",
		{"per_target_damage": 10, "energy_discard_count": 1})
	att.card.attacks[0].hits_each_defending = true
	var hp_before := tgt.current_hp
	var energy_before := tgt.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var tgt2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(tgt2.current_hp, hp_before, "tails → no damage")
	assert_eq(tgt2.attached_energy.size(), energy_before, "tails → no discard")


## (c) heads but defender has no energy → 10 dmg lands, no discard.
func test_dragon_crush_heads_no_energy() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})  # no energy
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true])
	_set_attack(att, 0, "gyarados_dragon_crush",
		{"per_target_damage": 10, "energy_discard_count": 1})
	att.card.attacks[0].hits_each_defending = true
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 10,
		"10 dmg lands even with no energy on defender")


## ── Lava Flow (DR_95 Magcargo ex) ──────────────────────────────────────────

## (a) Discard 0 → 40 base only.
func test_lava_flow_discard_zero() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_108_fire_energy", "RS_108_fire_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 40, "discard_basic_energy_for_bonus_each", {"bonus_per_discard": 20})
	_auto_answer_queries(mgr, [[] as Array[CardData]])  # discard nothing
	var hp_before := tgt.current_hp
	var energy_before := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 40,
		"0 discarded → 40 base only")
	assert_eq((mgr.board_position.get_instance("p0_active1") as PokemonInstance).attached_energy.size(), energy_before,
		"no energy discarded")


## (b) Discard 2 fires → 40 + 2×20 = 80.
func test_lava_flow_discard_two() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_108_fire_energy", "RS_108_fire_energy", "RS_108_fire_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 40, "discard_basic_energy_for_bonus_each", {"bonus_per_discard": 20})
	# Pre-grab references to the two energies the test wants to discard.
	var to_discard: Array[CardData] = [att.attached_energy[0], att.attached_energy[1]]
	_auto_answer_queries(mgr, [to_discard])
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 80,
		"2 discarded → 40 + 40 = 80")
	assert_eq((mgr.board_position.get_instance("p0_active1") as PokemonInstance).attached_energy.size(), 1,
		"2 energies discarded, 1 left")


## (c) No basic energy at all → no query, baseline 40 damage.
func test_lava_flow_no_basic_energy() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})  # no attached energy
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 40, "discard_basic_energy_for_bonus_each", {"bonus_per_discard": 20})
	var any_query := [false]
	mgr.attack_resolver.player_query_requested.connect(
		func(_q: AttackQuery) -> void: any_query[0] = true)
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 40,
		"baseline 40 with no energy to discard")
	assert_false(any_query[0], "no query fires when no basic energy attached")


## ── Dragon Burst (DR_97 Rayquaza ex) ───────────────────────────────────────

## (a) 3 Fire + 0 Lightning → auto-pick FIRE, 3 × 40 = 120.
func test_dragon_burst_auto_pick_only_type() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_108_fire_energy", "RS_108_fire_energy", "RS_108_fire_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "discard_all_of_chosen_type",
		{"types": ["FIRE", "LIGHTNING"], "damage_per_discard": 40})
	var any_query := [false]
	mgr.attack_resolver.player_query_requested.connect(
		func(_q: AttackQuery) -> void: any_query[0] = true)
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 120,
		"3 × 40 = 120")
	assert_eq((mgr.board_position.get_instance("p0_active1") as PokemonInstance).attached_energy.size(), 0,
		"all 3 Fires discarded")
	assert_false(any_query[0], "no type-picker when only one type is present")


## (b) 2 Fire + 2 Lightning → ask, pick LIGHTNING → 2 × 40 = 80.
func test_dragon_burst_pick_type() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_108_fire_energy", "RS_108_fire_energy",
					"RS_109_lightning_energy", "RS_109_lightning_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "discard_all_of_chosen_type",
		{"types": ["FIRE", "LIGHTNING"], "damage_per_discard": 40})
	_auto_answer_queries(mgr, ["LIGHTNING"])
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 80,
		"2 × 40 = 80")
	# Fires remain; Lightnings discarded.
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	var fire_left: int = 0
	for e: CardData in att2.attached_energy:
		if e is EnergyCardData and int((e as EnergyCardData).energy_type) == \
				PokemonCardData.EnergyType.FIRE:
			fire_left += 1
	assert_eq(fire_left, 2, "Fires preserved")
	assert_eq(att2.attached_energy.size(), 2, "only Fires remain")


## (c) Neither type → no damage, no discard (edge case: should never happen
## given costs in real play, but the handler must be robust).
func test_dragon_burst_none_of_chosen_types() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"]})  # only grass
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "discard_all_of_chosen_type",
		{"types": ["FIRE", "LIGHTNING"], "damage_per_discard": 40})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 0,
		"no eligible type → 0 damage")
	assert_eq((mgr.board_position.get_instance("p0_active1") as PokemonInstance).attached_energy.size(), 1,
		"no energy discarded")


## ── Double Bubble (SS_68 Marill) ───────────────────────────────────────────

## (a) 2 heads → 20 damage + defender Paralyzed.
func test_double_bubble_two_heads_paralyzes() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true, true])
	_set_attack(att, 10, "coin_multiply_damage", {"flips": 2, "any_heads_condition": "PARALYZED"})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var tgt2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - tgt2.current_hp, 20, "2 heads × 10 = 20")
	assert_true(tgt2.special_conditions.has(PokemonInstance.SpecialCondition.PARALYZED),
		"defender Paralyzed on any heads")


## (b) 1 head → 10 damage + Paralyzed.
func test_double_bubble_one_head_paralyzes() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true, false])
	_set_attack(att, 10, "coin_multiply_damage", {"flips": 2, "any_heads_condition": "PARALYZED"})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var tgt2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - tgt2.current_hp, 10, "1 head × 10 = 10")
	assert_true(tgt2.special_conditions.has(PokemonInstance.SpecialCondition.PARALYZED),
		"Paralyzed on any heads")


## (c) 0 heads → 0 damage + not paralyzed.
func test_double_bubble_zero_heads_no_status() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([false, false])
	_set_attack(att, 10, "coin_multiply_damage", {"flips": 2, "any_heads_condition": "PARALYZED"})
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var tgt2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(hp_before - tgt2.current_hp, 0, "0 heads → 0 damage")
	assert_false(tgt2.special_conditions.has(PokemonInstance.SpecialCondition.PARALYZED),
		"no status when 0 heads")


## ── Quick Touch (DR_18 Ninjask) ────────────────────────────────────────────

## (a) Confirm + 2 grass energies moved → swap + energies on new active.
func test_quick_touch_swap_and_move() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy", "RS_104_grass_energy"]})
	var bn := b.place_bench(0, "DR_5_golem", {})  # destination Pokémon
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 30, "may_switch_self_then_move_energy", {"energy_type": "GRASS"})
	# Queries: confirm-yes, [auto-pick swap since only 1 bench], confirm energies to move.
	# bench_options has 1 element, so handler auto-picks. Only 2 queries fire.
	var to_move: Array[CardData] = [att.attached_energy[0], att.attached_energy[1]]
	_auto_answer_queries(mgr, [true, to_move])
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# Bagon swapped with Golem.
	var new_active: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	var new_bench: PokemonInstance = mgr.board_position.get_instance("p0_bench1")
	assert_eq(new_active.card.card_id, bn.card.card_id, "Golem promoted to active")
	assert_eq(new_bench.card.card_id, att.card.card_id, "Bagon swapped to bench")
	# 2 grass moved from Bagon (bench) to Golem (active).
	assert_eq(new_active.attached_energy.size(), 2, "2 grass on new active")
	assert_eq(new_bench.attached_energy.size(), 1, "1 grass left on old active (bench)")


## (b) Decline → no swap, 30 damage lands normally.
func test_quick_touch_decline() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy"]})
	b.place_bench(0, "DR_5_golem", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 30, "may_switch_self_then_move_energy", {"energy_type": "GRASS"})
	_auto_answer_queries(mgr, [false])
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var still_active: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(still_active.card.card_id, att.card.card_id, "attacker stays")
	assert_eq(still_active.attached_energy.size(), 2, "no energy moved")
	assert_eq(hp_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 30,
		"30 damage lands normally")


## (c) Confirm + no grass on attacker → swap happens, no energy moves.
func test_quick_touch_swap_but_no_grass() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})  # no energy
	var bn := b.place_bench(0, "DR_5_golem", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 30, "may_switch_self_then_move_energy", {"energy_type": "GRASS"})
	# Confirm yes; bench auto-picked (1 option); no energy query because no grass on old.
	_auto_answer_queries(mgr, [true])
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var new_active: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(new_active.card.card_id, bn.card.card_id, "swap happened")
	assert_eq(new_active.attached_energy.size(), 0, "no energy on new active")


## ── JSON wiring smoke tests (real cards, real costs) ───────────────────────

## DR_31 Grovyle Fury Cutter JSON: cost 1G+1C, 4 coins all heads → 70.
func test_json_grovyle_fury_cutter() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_31_grovyle",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true, true, true, true])
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "Fury Cutter should resolve")
	# Grovyle is GRASS, Golem weakness is WATER → no W/R.
	assert_eq(hp_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 70,
		"4 heads → 10 + 60 = 70")


## SS_68 Marill Double Bubble JSON: cost 1W+1C, 2 heads → 20 + PAR.
func test_json_marill_double_bubble() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "SS_68_marill",
		{"energy": ["RS_106_water_energy", "RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true, true])
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var tgt2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	# Marill is WATER vs Golem (Fighting, weakness Water) → double damage.
	# 2 heads × 10 = 20, doubled = 40.
	assert_eq(hp_before - tgt2.current_hp, 40, "2 heads × 10 × 2 (weakness) = 40")
	assert_true(tgt2.special_conditions.has(PokemonInstance.SpecialCondition.PARALYZED),
		"defender Paralyzed")

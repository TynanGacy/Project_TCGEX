extends GutTest
## GUT test suite for Tier-3 Wave 18 (Hard / 2-active mode):
##   - RS_18 Nosepass Repulsion         (coin → defender + attached return to opp hand)
##   - RS_21 Seaking Fast Stream        (move 1 energy between two defenders)
##   - SS_99 Typhlosion ex Split Blast  (may split 100→50×each in 2-active mode)

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


## ── Repulsion (RS_18 Nosepass) ─────────────────────────────────────────────

## (a) Heads + opp has bench → defender + attached return to opp hand;
## opp's single bench Pokémon auto-promotes into the vacated active slot.
func test_repulsion_heads_returns_defender() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem",
		{"hp": 80, "energy": ["RS_106_water_energy", "RS_106_water_energy"]})
	b.place_bench(1, "DR_49_bagon", {})  # opp must have a bench
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true])
	_set_attack(att, 0, "coin_gate_return_defender_to_hand", {})
	var hand_before: int = mgr.game_position.hands[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# Single bench Pokémon auto-promoted into the vacated active slot.
	var promoted: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_not_null(promoted, "bench Pokémon auto-promoted to active")
	assert_eq(promoted.card.card_id, "DR_49_bagon",
		"the bench Bagon is now active")
	# Bench slot is now empty.
	assert_true(mgr.board_position.is_empty("p1_bench1"),
		"bench1 emptied by promotion")
	# Golem (1) + 2 water energy = 3 cards returned to opp hand.
	assert_eq(mgr.game_position.hands[1].size(), hand_before + 3,
		"defender card + 2 attached energies returned to opp hand")


## (b) Tails → no-op.
func test_repulsion_tails_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.place_bench(1, "DR_49_bagon", {})
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([false])
	_set_attack(att, 0, "coin_gate_return_defender_to_hand", {})
	var hand_before: int = mgr.game_position.hands[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_false(mgr.board_position.is_empty("p1_active1"), "defender still present")
	assert_eq(mgr.game_position.hands[1].size(), hand_before, "no hand additions")


## (c) Heads + opp has no bench AND no other active → no-op, defender stays.
func test_repulsion_heads_no_bench_no_other_active_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	# No bench, no active2.
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true])
	_set_attack(att, 0, "coin_gate_return_defender_to_hand", {})
	var hand_before: int = mgr.game_position.hands[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_false(mgr.board_position.is_empty("p1_active1"),
		"defender stays when opp has nothing else")
	assert_eq(mgr.game_position.hands[1].size(), hand_before, "no hand additions")


## (d) Heads + evolved defender → prior_stages also return to hand. The
## single bench Pokémon auto-promotes into the vacated active slot.
func test_repulsion_heads_evolved_defender_returns_prior_stages() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_41_shelgon", {"hp": 70})
	tgt.prior_stages.append(_lib.get_card("DR_49_bagon"))  # Bagon under Shelgon
	b.place_bench(1, "DR_49_bagon", {})  # ensure opp has bench
	b.set_prizes(0); b.set_prizes(1)
	mgr.push_forced_flips([true])
	_set_attack(att, 0, "coin_gate_return_defender_to_hand", {})
	var hand_before: int = mgr.game_position.hands[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# Shelgon + Bagon (prior stage) = 2 cards returned.
	assert_eq(mgr.game_position.hands[1].size(), hand_before + 2,
		"current + prior-stage cards return")
	# Bench auto-promoted; bench slot now empty.
	assert_true(mgr.board_position.is_empty("p1_bench1"),
		"bench emptied by promotion")
	var promoted: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_not_null(promoted, "bench Pokémon promoted into vacated active slot")


## ── Fast Stream (RS_21 Seaking) ────────────────────────────────────────────

## (a) Two defenders + target has energy → energy moves to other defender.
func test_fast_stream_moves_energy() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem",
		{"hp": 120, "energy": ["RS_106_water_energy"]})
	var other := b.place_active2(1, "DR_49_bagon", {})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 30, "move_one_energy_between_defenders", {})
	var src_energy_before := tgt.attached_energy.size()
	var dst_energy_before := other.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var src: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var dst: PokemonInstance = mgr.board_position.get_instance("p1_active2")
	assert_eq(src.attached_energy.size(), src_energy_before - 1, "energy left target")
	assert_eq(dst.attached_energy.size(), dst_energy_before + 1, "energy gained on other defender")


## (b) Only 1 defender → no-op (no other_slot to move to).
func test_fast_stream_only_one_defender_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem",
		{"hp": 120, "energy": ["RS_106_water_energy"]})
	# No p1_active2.
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 30, "move_one_energy_between_defenders", {})
	var energy_before := tgt.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var src: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	assert_eq(src.attached_energy.size(), energy_before, "energy unchanged")


## (c) Two defenders + target has no energy → no-op.
func test_fast_stream_no_energy_on_target_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})  # no energy
	var other := b.place_active2(1, "DR_49_bagon",
		{"energy": ["RS_106_water_energy"]})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 30, "move_one_energy_between_defenders", {})
	var other_before := other.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var dst: PokemonInstance = mgr.board_position.get_instance("p1_active2")
	assert_eq(dst.attached_energy.size(), other_before, "other defender unchanged")


## ── Split Blast (SS_99 Typhlosion ex) ──────────────────────────────────────

## (a) Only 1 defender → 100 forced to chosen, no query.
func test_split_blast_one_defender_forces_full() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {"energy": ["RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	# Chain: may_split + discard.
	_set_attack(att, 0, "may_split_damage_each",
		{"full": 100, "split": 50},
		[{"key": "discard_energy", "params": {"type": "ANY", "count": 1}}])
	var any_query := [false]
	mgr.attack_resolver.player_query_requested.connect(
		func(_q: AttackQuery) -> void: any_query[0] = true)
	var hp_before := tgt.current_hp
	var energy_before := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var tgt2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	# Bagon is COLORLESS; Golem weakness WATER — no W/R. 100 dmg.
	assert_eq(hp_before - tgt2.current_hp, 100, "single defender → 100")
	assert_false(any_query[0], "no query when 1 defender")
	# Discard from chain.
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(att2.attached_energy.size(), energy_before - 1, "1 energy discarded")


## (b) Two defenders + decline → 100 to chosen, other untouched.
func test_split_blast_two_defenders_decline() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {"energy": ["RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 200})
	var other := b.place_active2(1, "DR_5_golem", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "may_split_damage_each",
		{"full": 100, "split": 50},
		[{"key": "discard_energy", "params": {"type": "ANY", "count": 1}}])
	_auto_answer_queries(mgr, [false])  # decline split
	var hp_before := tgt.current_hp
	var other_hp_before := other.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var tgt2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var other2: PokemonInstance = mgr.board_position.get_instance("p1_active2")
	assert_eq(hp_before - tgt2.current_hp, 100, "chosen takes 100")
	assert_eq(other_hp_before - other2.current_hp, 0, "other defender unscathed")


## (c) Two defenders + accept → 50 to each.
func test_split_blast_two_defenders_accept_split() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {"energy": ["RS_104_grass_energy"]})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 200})
	var other := b.place_active2(1, "DR_5_golem", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "may_split_damage_each",
		{"full": 100, "split": 50},
		[{"key": "discard_energy", "params": {"type": "ANY", "count": 1}}])
	_auto_answer_queries(mgr, [true])  # accept split
	var hp_before := tgt.current_hp
	var other_hp_before := other.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var tgt2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	var other2: PokemonInstance = mgr.board_position.get_instance("p1_active2")
	assert_eq(hp_before - tgt2.current_hp, 50, "active1 takes 50")
	assert_eq(other_hp_before - other2.current_hp, 50, "active2 takes 50")


## (d) Energy discard happens in all paths (verified across the cluster above).
func test_split_blast_discard_always_fires() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy", "RS_104_grass_energy"]})
	b.place_active(1, "DR_5_golem", {"hp": 200})
	b.place_active2(1, "DR_5_golem", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "may_split_damage_each",
		{"full": 100, "split": 50},
		[{"key": "discard_energy", "params": {"type": "ANY", "count": 1}}])
	_auto_answer_queries(mgr, [true])  # accept
	var energy_before := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var att2: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	assert_eq(att2.attached_energy.size(), energy_before - 1, "1 energy discarded")

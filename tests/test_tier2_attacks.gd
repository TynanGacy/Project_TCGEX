extends GutTest
## GUT test suite for tier-2 attack effect handlers.
##
## Covers:
##   attach_from_hand — SS_78_shroomish (Growth Spurt)
##   bench_damage     — DR_36_marshtomp, DR_55_geodude, RS_4_camerupt,
##                      RS_21_seaking, RS_23_swampert, SS_35_electabuzz,
##                      SS_47_murkrow, SS_62_duskull
##
## All attack tests use request_action_async() so post-actions and the bench-
## target query are observed in the assertion phase. Tests that need a query
## answer connect to player_query_requested before issuing the action.

var _lib: CardLibrary
var _handlers_node: Node = null


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")
	## effect_handlers.gd is normally instantiated by the match scene, which
	## isn't loaded in GUT. Spin it up here so EffectRegistry has handlers.
	## NOTE: Use plain add_child (not add_child_autoqfree) — autoqfree frees
	## the node at end of the FIRST test, but the registered handler closures
	## capture `self`, so subsequent tests would crash on null lambda calls.
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


## Connects a one-shot resolver for the next bench-target query.
## Uses call_deferred so the resolver has time to reach its await point on
## player_query_resolved before we emit it — emitting synchronously inside
## the player_query_requested handler would fire before the resolver is
## listening, causing the await to hang forever.
func _auto_answer_bench_query(mgr: ManagerSystem, slot: String) -> void:
	mgr.attack_resolver.player_query_requested.connect(
		func(_q) -> void: mgr.attack_resolver.resolve_query.call_deferred(slot),
		CONNECT_ONE_SHOT
	)


func _count_energy_of_type(inst: PokemonInstance, type_str: String) -> int:
	var et: int = PokemonCardData.EnergyType[type_str]
	var n := 0
	for e: CardData in inst.attached_energy:
		if e is EnergyCardData and int((e as EnergyCardData).energy_type) == et:
			n += 1
	return n


## ── attach_from_hand: SS_78_shroomish "Growth Spurt" ──────────────────────────

func test_attach_from_hand_self_grass() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "SS_78_shroomish", {"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_41_shelgon", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	b.give_hand(0, ["RS_104_grass_energy"])

	var pre := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_true(r.ok, "Growth Spurt should succeed")
	assert_eq(att.attached_energy.size(), pre + 1,
		"Shroomish should gain exactly 1 Grass energy from hand")
	assert_eq(_count_energy_of_type(att, "GRASS"), 2,
		"Attacker should now have 2 Grass energies attached")


func test_attach_from_hand_filters_non_grass() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "SS_78_shroomish", {"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_41_shelgon", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	b.give_hand(0, ["RS_108_fire_energy", "RS_104_grass_energy"])

	await mgr.request_action_async(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))

	var hand: Array = mgr.game_position.hands[0]
	assert_eq(hand.size(), 1, "One card should remain in hand (Fire)")
	if hand.size() == 1:
		assert_true(hand[0] is EnergyCardData, "Remaining card should be energy")
		assert_eq(int((hand[0] as EnergyCardData).energy_type),
			int(PokemonCardData.EnergyType.FIRE),
			"Remaining card should be the Fire energy (Grass was consumed)")
	assert_eq(_count_energy_of_type(att, "GRASS"), 2,
		"Attacker now has 2 Grass attached")
	assert_eq(_count_energy_of_type(att, "FIRE"), 0,
		"Fire was filtered out and not attached")


func test_attach_from_hand_count_param_two() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "SS_78_shroomish", {"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_41_shelgon", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	b.give_hand(0, ["RS_104_grass_energy", "RS_104_grass_energy"])

	att.card.attacks[0].effect_params = {"type": "GRASS", "count": 2, "target": "self"}

	await mgr.request_action_async(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))

	assert_eq(_count_energy_of_type(att, "GRASS"), 3,
		"Attacker should have 1 starting + 2 attached = 3 Grass energies")
	assert_eq((mgr.game_position.hands[0] as Array).size(), 0,
		"Both Grass cards should have been removed from hand")


func test_attach_from_hand_empty_hand_no_op() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "SS_78_shroomish", {"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_41_shelgon", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)

	var pre := att.attached_energy.size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_true(r.ok, "Growth Spurt should still succeed with empty hand")
	assert_eq(att.attached_energy.size(), pre,
		"Attached energy unchanged when hand is empty")


func test_attach_from_hand_no_matching_type() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "SS_78_shroomish", {"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_41_shelgon", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	b.give_hand(0, ["RS_108_fire_energy"])

	var pre := att.attached_energy.size()
	await mgr.request_action_async(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))

	assert_eq(att.attached_energy.size(), pre,
		"No attachment when no matching energy type is in hand")
	assert_eq((mgr.game_position.hands[0] as Array).size(), 1,
		"Non-matching energy stays in hand")


## ── bench_damage ─────────────────────────────────────────────────────────────

func test_bench_damage_no_bench_no_query() -> void:
	## With no opponent bench, the bench_damage handler returns early without
	## emitting a query. Active still takes base damage.
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "DR_36_marshtomp", {
		"energy": ["RS_106_water_energy", "RS_104_grass_energy"]
	})
	var tgt := b.place_active(1, "DR_41_shelgon", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)

	var query_count := [0]
	mgr.attack_resolver.player_query_requested.connect(
		func(_q) -> void: query_count[0] += 1
	)

	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_true(r.ok, "Mud Splash should succeed with no bench")
	assert_eq(query_count[0], 0, "No bench-target query should be emitted with empty bench")
	assert_lt(tgt.current_hp, 200, "Active still takes the base 20 damage")


func test_bench_damage_marshtomp_routes_to_chosen_slot() -> void:
	## Mud Splash deals 20 to active + 10 to chosen bench (unmodified).
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "DR_36_marshtomp", {
		"energy": ["RS_106_water_energy", "RS_104_grass_energy"]
	})
	var active_tgt := b.place_active(1, "DR_41_shelgon", {"hp": 200})
	var bench_pick := b.place_bench(1, "DR_49_bagon", {"hp": 60})
	var bench_other := b.place_bench(1, "DR_49_bagon", {"hp": 60})
	b.set_prizes(0); b.set_prizes(1)

	_auto_answer_bench_query(mgr, "p1_bench1")
	await mgr.request_action_async(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))

	assert_lt(active_tgt.current_hp, 200, "Active target took base damage")
	assert_eq(bench_pick.current_hp, 50,
		"Chosen bench slot took exactly 10 damage (60 → 50)")
	assert_eq(bench_other.current_hp, 60,
		"Non-chosen bench slot is untouched")


func test_bench_damage_thunder_spear_zero_to_active() -> void:
	## Electabuzz Thunder Spear has base_damage=0 → only the bench target
	## takes damage (40, unmodified).
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "SS_35_electabuzz", {
		"energy": ["RS_109_lightning_energy", "RS_104_grass_energy", "RS_104_grass_energy"]
	})
	var active_tgt := b.place_active(1, "DR_41_shelgon", {"hp": 200})
	var bench_pick := b.place_bench(1, "DR_49_bagon", {"hp": 60})
	b.set_prizes(0); b.set_prizes(1)

	_auto_answer_bench_query(mgr, "p1_bench1")
	## Thunder Spear is attack index 1.
	await mgr.request_action_async(ActionAttack.new(0, "p0_active1", 1, "p1_active1"))

	assert_eq(active_tgt.current_hp, 200,
		"Active untouched by Thunder Spear (base_damage=0)")
	assert_eq(bench_pick.current_hp, 20,
		"Bench target should take exactly 40 damage (60 → 20)")


func test_bench_damage_unmodified_ignores_weakness() -> void:
	## Marshtomp deals 10 unmodified to a bench Pokémon weak to Water.
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "DR_36_marshtomp", {
		"energy": ["RS_106_water_energy", "RS_104_grass_energy"]
	})
	b.place_active(1, "DR_41_shelgon", {"hp": 200})
	var bench_pick := b.place_bench(1, "DR_49_bagon", {"hp": 60})
	b.set_prizes(0); b.set_prizes(1)

	## Force a Water weakness on the bench target's card.
	(bench_pick.card as PokemonCardData).weakness = PokemonCardData.EnergyType.WATER

	_auto_answer_bench_query(mgr, "p1_bench1")
	await mgr.request_action_async(ActionAttack.new(0, "p0_active1", 0, "p1_active1"))

	## unmodified=true → still exactly 10 damage; weakness ignored.
	assert_eq(bench_pick.current_hp, 50,
		"unmodified bench damage ignores weakness (60 → 50, not 60 → 40)")


func test_bench_damage_knockout_triggers_resolve() -> void:
	## Bench target at 10 HP gets KO'd by 40-damage Thunder Spear.
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "SS_35_electabuzz", {
		"energy": ["RS_109_lightning_energy", "RS_104_grass_energy", "RS_104_grass_energy"]
	})
	b.place_active(1, "DR_41_shelgon", {"hp": 200})
	var bench_pick := b.place_bench(1, "DR_49_bagon", {"hp": 10})
	b.set_prizes(0); b.set_prizes(1)

	_auto_answer_bench_query(mgr, "p1_bench1")
	await mgr.request_action_async(ActionAttack.new(0, "p0_active1", 1, "p1_active1"))

	assert_true(bench_pick.is_knocked_out(),
		"Bench target should be KO'd after 40 damage to a 10-HP Pokémon")
	## resolve_knockout should at minimum vacate the slot or queue a prize prompt.
	assert_true(mgr.prize_selection_phase_for == 0
			or mgr.board_position.is_empty("p1_bench1"),
		"Manager should reflect KO bookkeeping (prize prompt or slot vacated)")


func test_bench_damage_query_options_are_only_filled_bench_slots() -> void:
	## With 1 filled bench slot and 4 empty, the query options should contain
	## exactly that one slot.
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "SS_47_murkrow", {
		"energy": ["RS_93_darkness_energy", "RS_104_grass_energy"]
	})
	b.place_active(1, "DR_41_shelgon", {"hp": 200})
	b.place_bench(1, "DR_49_bagon", {"hp": 60})
	b.set_prizes(0); b.set_prizes(1)

	var captured: Array = []
	mgr.attack_resolver.player_query_requested.connect(
		func(q: AttackQuery) -> void:
			captured.append(q)
			mgr.attack_resolver.resolve_query.call_deferred("p1_bench1"),
		CONNECT_ONE_SHOT
	)
	## Murkrow Dark Mind is attack index 1.
	await mgr.request_action_async(ActionAttack.new(0, "p0_active1", 1, "p1_active1"))

	assert_eq(captured.size(), 1, "One bench-target query should have been emitted")
	if captured.size() == 1:
		var q: AttackQuery = captured[0]
		assert_eq(q.kind, AttackQuery.Kind.CHOOSE_BENCH_TARGET,
			"Query kind should be CHOOSE_BENCH_TARGET")
		assert_eq((q.options as Array), ["p1_bench1"],
			"Only filled bench slots should be in options")


## ── effect_params parsed correctly from JSON for all 9 cards ──────────────────

func test_all_tier2_cards_have_expected_effect_keys() -> void:
	var expected := {
		"SS_78_shroomish":   {"idx": 0, "key": "attach_from_hand"},
		"DR_36_marshtomp":   {"idx": 0, "key": "bench_damage"},
		"DR_55_geodude":     {"idx": 1, "key": "bench_damage"},
		"RS_4_camerupt":     {"idx": 0, "key": "bench_damage"},
		"RS_21_seaking":     {"idx": 0, "key": "bench_damage"},
		"RS_23_swampert":    {"idx": 0, "key": "bench_damage"},
		"SS_35_electabuzz":  {"idx": 1, "key": "bench_damage"},
		"SS_47_murkrow":     {"idx": 1, "key": "bench_damage"},
		"SS_62_duskull":     {"idx": 1, "key": "bench_damage"},
	}
	for card_id in expected:
		var spec: Dictionary = expected[card_id]
		var card := _lib.get_card(card_id) as PokemonCardData
		assert_not_null(card, "%s should be loadable" % card_id)
		if card == null:
			continue
		var idx: int = spec["idx"]
		assert_true(card.attacks.size() > idx,
			"%s should have an attack at index %d" % [card_id, idx])
		assert_eq(card.attacks[idx].effect_key, spec["key"],
			"%s attack[%d] should have effect_key=%s" % [card_id, idx, spec["key"]])
		assert_not_null(card.attacks[idx].effect_params,
			"%s attack[%d] should have effect_params" % [card_id, idx])

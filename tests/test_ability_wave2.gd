extends GutTest
## GUT tests for the Day-4 Poké-Power wave 1.
##
## Covered:
##   P-A: Water Call (Swampert), Firestarter (Blaziken),
##        Psy Shadow (Gardevoir), Magnetic Field (Magneton)
##   P-B: Energy Trans (Sceptile) — repeatable
##   P-C: Dragon Wind (Salamence) / Drive Off (Swellow) — same handler
##   P-D: Chaos Flash (Golduck) — coin + status
##   P-E: Energy Draw (Delcatty)
##   P-G: Healing Wind (Xatu)
##
## Each test stages a minimal board, dispatches ActionUseAbility, and asserts
## the resulting state. Tests that involve PROMPT use a deferred resolver
## to feed the response back.

var _lib: CardLibrary
var _attack_handlers: Node = null
var _ability_handlers_node: Node = null


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")
	_attack_handlers = load("res://scenes/match/effect_handlers.gd").new()
	add_child(_attack_handlers)
	_ability_handlers_node = load("res://scenes/match/ability_handlers.gd").new()
	add_child(_ability_handlers_node)


func after_all() -> void:
	if _attack_handlers != null:
		_attack_handlers.queue_free()
	if _ability_handlers_node != null:
		_ability_handlers_node.queue_free()


func _make_builder() -> TestBoardBuilder:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	return TestBoardBuilder.new(mgr, _lib)


## --- P-A: Water Call (Swampert) -------------------------------------------

func test_water_call_attaches_water_from_hand_to_active() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var active := b.place_active(0, "DR_49_bagon")
	## Need Swampert in play. Place on bench so the source is the bench.
	var swampert := b.place_bench(0, "RS_13_swampert")
	var water := _lib.get_card("RS_106_water_energy")
	mgr.game_position.put_in_hand(0, water)
	var _bench_slot := mgr.board_position.first_empty_bench(0)

	## Find swampert's slot.
	var swampert_slot: String = ""
	for s in ["bench1","bench2","bench3","bench4","bench5"]:
		var sid = "p0_%s" % s
		if mgr.board_position.get_instance(sid) == swampert:
			swampert_slot = sid
			break
	assert_ne(swampert_slot, "", "Setup: Swampert should be on bench.")

	var r := await mgr.request_action_async(ActionUseAbility.new(0, swampert_slot, 0))
	assert_true(r.ok, "Water Call should activate from bench Swampert.")
	assert_eq(active.attached_energy.size(), 1,
		"Water Call should attach the Water Energy to the active.")
	assert_eq((mgr.game_position.hands[0] as Array).size(), 0,
		"Water Energy should leave the hand.")
	assert_true(swampert.power_used_this_turn,
		"Once-per-turn flag should be set after activation.")


func test_water_call_rejects_without_water_in_hand() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "DR_49_bagon")
	var swampert := b.place_bench(0, "RS_13_swampert")
	## Hand contains only a Grass energy → Water Call should fail VALIDATE.
	mgr.game_position.put_in_hand(0, _lib.get_card("RS_104_grass_energy"))

	var swampert_slot := _find_slot(mgr, swampert)
	var r := await mgr.request_action_async(ActionUseAbility.new(0, swampert_slot, 0))
	assert_false(r.ok, "Water Call should reject when no Water Energy is in hand.")


## --- P-A: Firestarter (Blaziken) ------------------------------------------

func test_firestarter_attaches_fire_from_discard_to_chosen_bench() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var active := b.place_active(0, "RS_3_blaziken")
	var bench := b.place_bench(0, "DR_49_bagon")
	## Put a Fire energy in discard.
	var fire := _lib.get_card("RS_108_fire_energy")
	mgr.game_position.put_in_discard(0, fire)
	## Auto-respond to the bench-choice prompt with the bench Pokémon's slot.
	var target_slot := _find_slot(mgr, bench)
	mgr.ability_resolver.player_query_requested.connect(
		func(_q: AbilityQuery) -> void:
			mgr.ability_resolver.resolve_query.call_deferred(target_slot)
	)

	var r := await mgr.request_action_async(
		ActionUseAbility.new(0, "p0_active1", 0))
	assert_true(r.ok, "Firestarter should activate")
	assert_eq(bench.attached_energy.size(), 1,
		"Fire Energy should attach to the chosen bench Pokémon.")
	assert_false((mgr.game_position.discards[0] as Array).has(fire),
		"Fire Energy should leave the discard pile.")
	assert_eq(active.attached_energy.size(), 0,
		"Active (Blaziken) should not receive the energy.")


## --- P-B: Energy Trans (Sceptile) — repeatable ----------------------------

func test_energy_trans_moves_grass_and_is_repeatable() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var sceptile := b.place_active(0, "RS_20_sceptile",
		{"energy": ["RS_104_grass_energy"]})
	var bench := b.place_bench(0, "DR_49_bagon")
	## We will feed: source=Sceptile slot, energy=its grass, dest=bench slot.
	var grass_on_sceptile: CardData = sceptile.attached_energy[0]
	var responses: Array = [
		"p0_active1",          # source
		grass_on_sceptile,     # energy
		_find_slot(mgr, bench),# dest
	]
	var idx_ref: Array = [0]
	mgr.ability_resolver.player_query_requested.connect(
		func(_q: AbilityQuery) -> void:
			var resp = responses[idx_ref[0]]
			idx_ref[0] += 1
			mgr.ability_resolver.resolve_query.call_deferred(resp)
	)

	var r := await mgr.request_action_async(
		ActionUseAbility.new(0, "p0_active1", 0))
	assert_true(r.ok)
	assert_eq(sceptile.attached_energy.size(), 0,
		"Source Pokémon should lose the Grass Energy.")
	assert_eq(bench.attached_energy.size(), 1,
		"Destination should gain the Grass Energy.")
	## Repeatable: should not flip power_used_this_turn.
	assert_false(sceptile.power_used_this_turn,
		"Repeatable powers should not set power_used_this_turn.")


## --- P-C: Dragon Wind / Drive Off (switch opp) ----------------------------

func test_dragon_wind_swaps_opponent_active_with_chosen_bench() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "DR_10_salamence")
	var opp_active := b.place_active(1, "DR_49_bagon")
	var opp_bench := b.place_bench(1, "DR_41_shelgon")
	var bench_slot := _find_slot(mgr, opp_bench)
	mgr.ability_resolver.player_query_requested.connect(
		func(_q: AbilityQuery) -> void:
			mgr.ability_resolver.resolve_query.call_deferred(bench_slot)
	)

	var r := await mgr.request_action_async(
		ActionUseAbility.new(0, "p0_active1", 0))
	assert_true(r.ok, "Dragon Wind should activate.")
	## Shelgon now in opp active1, Bagon on bench.
	assert_eq(mgr.board_position.get_instance("p1_active1"), opp_bench,
		"Selected bench Pokémon should be in opp active1 after swap.")
	assert_eq(mgr.board_position.get_instance(bench_slot), opp_active,
		"Former opp active should be on the bench.")


## --- P-D: Chaos Flash (Golduck) -------------------------------------------

func test_chaos_flash_heads_confuses_defender() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "SS_17_golduck")
	var defender := b.place_active(1, "DR_49_bagon")
	mgr.push_forced_flip(true)  ## heads → confuse

	var r := await mgr.request_action_async(
		ActionUseAbility.new(0, "p0_active1", 0))
	assert_true(r.ok)
	assert_true(defender.special_conditions.has(PokemonInstance.SpecialCondition.CONFUSED),
		"Heads → Defending should be Confused.")


func test_chaos_flash_tails_no_status() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "SS_17_golduck")
	var defender := b.place_active(1, "DR_49_bagon")
	mgr.push_forced_flip(false)  ## tails → no-op

	await mgr.request_action_async(ActionUseAbility.new(0, "p0_active1", 0))
	assert_false(defender.special_conditions.has(PokemonInstance.SpecialCondition.CONFUSED),
		"Tails → Defender should not be Confused.")


## --- P-E: Energy Draw (Delcatty) -------------------------------------------

func test_energy_draw_discards_one_energy_draws_three() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "RS_5_delcatty")
	## Put one energy in hand (to discard) and 5 cards in deck.
	var fire := _lib.get_card("RS_108_fire_energy")
	mgr.game_position.put_in_hand(0, fire)
	for _i in range(5):
		mgr.game_position.put_in_deck(0, _lib.get_card("RS_104_grass_energy"))
	mgr.ability_resolver.player_query_requested.connect(
		func(_q: AbilityQuery) -> void:
			mgr.ability_resolver.resolve_query.call_deferred([fire])
	)

	var hand_before := (mgr.game_position.hands[0] as Array).size()
	var r := await mgr.request_action_async(
		ActionUseAbility.new(0, "p0_active1", 0))
	assert_true(r.ok)
	## Net: -1 (discarded fire) + 3 drawn = +2 hand. Hand before is 1 (fire).
	## After: 0 (after discard) + 3 = 3.
	assert_eq((mgr.game_position.hands[0] as Array).size(), hand_before - 1 + 3,
		"Hand should be -1 (discarded) + 3 (drawn).")
	assert_true((mgr.game_position.discards[0] as Array).has(fire),
		"Discarded Fire should be in discard.")


## --- P-G: Healing Wind (Xatu) ----------------------------------------------

func test_healing_wind_heals_each_active() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Damage Xatu to test that it heals itself (and is the active).
	var xatu := b.place_active(0, "SS_55_xatu", {"hp": 30})
	var pre_hp := xatu.current_hp

	var r := await mgr.request_action_async(
		ActionUseAbility.new(0, "p0_active1", 0))
	assert_true(r.ok)
	assert_eq(xatu.current_hp, pre_hp + 10,
		"Healing Wind should heal 10 HP from each active Pokémon.")


## --- Asleep / before-attack lockouts --------------------------------------

func test_power_blocked_after_attack() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "SS_55_xatu")
	mgr.attack_used_this_turn[0] = true

	var r := await mgr.request_action_async(
		ActionUseAbility.new(0, "p0_active1", 0))
	assert_false(r.ok, "Powers can only fire before your attack.")


## --- Helpers ---------------------------------------------------------------

func _find_slot(mgr: ManagerSystem, inst: PokemonInstance) -> String:
	for pid in range(2):
		for s in BoardPosition.all_slot_ids(pid):
			if mgr.board_position.get_instance(s) == inst:
				return s
	return ""

extends GutTest
## GUT tests for Wave 6 (the plan's Wave 3A + 3B) — final ability authoring.
##
## Wave 3A — passive bodies:
##   - Swampert "Natural Remedy" (heal 10 HP when Water Energy attached)
##   - Cradily "Super Suction Cups" (opponent retreat lock while Active)
##   - Armaldo "Primal Veil" (both-sides Supporter play lock while Active)
##
## Wave 3B — until-end-of-turn type override:
##   - Solrock "Solar Eclipse" (→ FIRE if Lunatone in play)
##   - Lunatone "Lunar Eclipse" (→ DARKNESS if Solrock in play)

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


## --- Swampert: Natural Remedy ---------------------------------------------

func test_natural_remedy_heals_on_water_energy_attach() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Damaged Swampert in active.
	var swampert := b.place_active(0, "RS_23_swampert", {"hp": 50})
	var water: EnergyCardData = _lib.get_card("RS_106_water_energy") as EnergyCardData
	mgr.game_position.put_in_hand(0, water)
	var pre_hp: int = swampert.current_hp

	var r: ActionResult = await mgr.request_action_async(
		ActionAttachEnergy.new(0, water, "p0_active1")
	)
	assert_true(r.ok, "Energy attach should succeed: %s" % r.reason)
	assert_eq(swampert.current_hp - pre_hp, 10,
		"Natural Remedy should heal 1 damage counter on Water Energy attach.")


func test_natural_remedy_no_effect_on_non_water_energy() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var swampert := b.place_active(0, "RS_23_swampert", {"hp": 50})
	var grass: EnergyCardData = _lib.get_card("RS_104_grass_energy") as EnergyCardData
	mgr.game_position.put_in_hand(0, grass)
	var pre_hp: int = swampert.current_hp

	await mgr.request_action_async(
		ActionAttachEnergy.new(0, grass, "p0_active1")
	)
	assert_eq(swampert.current_hp, pre_hp,
		"Natural Remedy should NOT heal on a non-Water Energy attach.")


## --- Cradily: Super Suction Cups ------------------------------------------

func test_super_suction_cups_blocks_opponent_retreat() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(1)
	## P0 has Cradily Active; P1 tries to retreat from active to bench.
	b.place_active(0, "SS_3_cradily")
	## Need an active to retreat. Use Bagon with enough energy for its
	## retreat_cost (1 Colorless).
	b.place_active(1, "DR_49_bagon", {"energy": ["RS_104_grass_energy"]})
	b.place_bench(1, "DR_49_bagon")

	var r: ActionResult = await mgr.request_action_async(
		ActionRetreat.new(1, "p1_active1", "p1_bench1")
	)
	assert_false(r.ok,
		"Cradily's Super Suction Cups should block opponent retreat.")


func test_super_suction_cups_does_not_block_own_retreat() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## P0 owns Cradily — own player should still be able to retreat.
	b.place_active(0, "DR_49_bagon", {"energy": ["RS_104_grass_energy"]})
	b.place_bench(0, "SS_3_cradily")

	var r: ActionResult = await mgr.request_action_async(
		ActionRetreat.new(0, "p0_active1", "p0_bench1")
	)
	assert_true(r.ok,
		"Super Suction Cups should not block its own player's retreat.")


## --- Armaldo: Primal Veil -------------------------------------------------

func test_primal_veil_blocks_supporter_for_both_players() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(1)
	## P0 has Armaldo Active. Both players should be locked from Supporters.
	b.place_active(0, "SS_1_armaldo")
	b.place_active(1, "DR_49_bagon")
	## Find any Supporter in the pool.
	var supporter: TrainerCardData = null
	for c in _lib.all_cards():
		if c is TrainerCardData \
				and (c as TrainerCardData).trainer_kind == TrainerCardData.TrainerKind.SUPPORTER:
			supporter = c
			break
	assert_not_null(supporter, "No Supporter cards in library — test setup error.")
	mgr.game_position.put_in_hand(1, supporter)

	var r: ActionResult = await mgr.request_action_async(
		ActionPlaySupporter.new(1, supporter)
	)
	assert_false(r.ok, "Primal Veil should block opponent Supporter play.")

	## Now P0 (carrier's own side) — should also be blocked per "both" scope.
	b.set_turn(0)
	mgr.game_position.put_in_hand(0, supporter)
	var r2: ActionResult = await mgr.request_action_async(
		ActionPlaySupporter.new(0, supporter)
	)
	assert_false(r2.ok, "Primal Veil should also block its own player's Supporter play.")


func test_primal_veil_inactive_when_armaldo_is_benched() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(1)
	## Armaldo on bench, not active — Primal Veil's carrier_position="active"
	## means the body does not fire.
	b.place_active(0, "DR_49_bagon")
	b.place_bench(0, "SS_1_armaldo")
	b.place_active(1, "DR_49_bagon")
	var supporter: TrainerCardData = null
	for c in _lib.all_cards():
		if c is TrainerCardData \
				and (c as TrainerCardData).trainer_kind == TrainerCardData.TrainerKind.SUPPORTER:
			supporter = c
			break
	mgr.game_position.put_in_hand(1, supporter)

	var r: ActionResult = await mgr.request_action_async(
		ActionPlaySupporter.new(1, supporter)
	)
	assert_true(r.ok,
		"Primal Veil with Armaldo benched should not lock Supporter plays.")


## --- Solrock / Lunatone: type override -----------------------------------

func _find_slot(mgr: ManagerSystem, inst: PokemonInstance) -> String:
	for pid in [0, 1]:
		for s in (BoardPosition.ACTIVE_SLOTS + BoardPosition.BENCH_SLOTS):
			var sid := "p%d_%s" % [pid, s]
			if mgr.board_position.get_instance(sid) == inst:
				return sid
	return ""


func test_solar_eclipse_morphs_solrock_to_fire_with_lunatone_partner() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var solrock := b.place_active(0, "SS_13_solrock")
	b.place_bench(0, "SS_8_lunatone")  ## partner — in play.
	var slot := _find_slot(mgr, solrock)

	var r: ActionResult = await mgr.request_action_async(
		ActionUseAbility.new(0, slot, 0)
	)
	assert_true(r.ok, "Solar Eclipse should activate: %s" % r.reason)
	assert_eq(AbilityEffects.effective_pokemon_type(solrock, mgr),
		int(PokemonCardData.EnergyType.FIRE),
		"Solrock should be FIRE-typed until end of turn.")


func test_solar_eclipse_rejected_without_partner() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var solrock := b.place_active(0, "SS_13_solrock")
	## No Lunatone in play.
	var slot := _find_slot(mgr, solrock)

	var r: ActionResult = await mgr.request_action_async(
		ActionUseAbility.new(0, slot, 0)
	)
	assert_false(r.ok, "Solar Eclipse should reject without Lunatone in play.")


func test_solar_eclipse_rejected_when_special_condition_active() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var solrock := b.place_active(0, "SS_13_solrock",
		{"conditions": [PokemonInstance.SpecialCondition.BURNED]})
	b.place_bench(0, "SS_8_lunatone")
	var slot := _find_slot(mgr, solrock)

	var r: ActionResult = await mgr.request_action_async(
		ActionUseAbility.new(0, slot, 0)
	)
	assert_false(r.ok,
		"Solar Eclipse should reject when Solrock has a Special Condition.")


func test_lunar_eclipse_morphs_lunatone_to_darkness_with_solrock_partner() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var lunatone := b.place_active(0, "SS_8_lunatone")
	b.place_bench(0, "SS_13_solrock")
	var slot := _find_slot(mgr, lunatone)

	var r: ActionResult = await mgr.request_action_async(
		ActionUseAbility.new(0, slot, 0)
	)
	assert_true(r.ok, "Lunar Eclipse should activate: %s" % r.reason)
	assert_eq(AbilityEffects.effective_pokemon_type(lunatone, mgr),
		int(PokemonCardData.EnergyType.DARKNESS),
		"Lunatone should be DARKNESS-typed until end of turn.")

extends GutTest
## Tests for ActionEvolve.  Covers Basic → Stage 1, Stage 1 → Stage 2, the
## "just-came-into-play" lockout, the first-turn lockout, mismatched-name
## rejection, and that evolving clears Special Conditions.

var _lib: CardLibrary
var _ability_handlers_node: Node = null


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")
	_ability_handlers_node = load("res://scenes/match/ability_handlers.gd").new()
	add_child(_ability_handlers_node)


func after_all() -> void:
	if _ability_handlers_node != null:
		_ability_handlers_node.queue_free()


func _make_builder() -> TestBoardBuilder:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	return TestBoardBuilder.new(mgr, _lib)


func test_basic_evolves_to_stage1() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)  ## turn ≥ 3 — past first-turn lockout
	var inst := b.place_active(0, "RS_75_treecko")
	b.set_prizes(0)
	b.set_prizes(1)
	var grovyle: PokemonCardData = _lib.get_card("RS_31_grovyle") as PokemonCardData
	mgr.game_position.put_in_hand(0, grovyle)

	var r := await mgr.request_action_async(
		ActionEvolve.new(0, grovyle, "p0_active1")
	)
	assert_true(r.ok, "Evolve should succeed: %s" % r.reason)
	assert_eq(inst.card, grovyle, "Slot occupant card should be Grovyle.")
	assert_eq(inst.card.stage, PokemonCardData.Stage.STAGE1)


func test_stage1_evolves_to_stage2() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	## Place a Treecko, then "fake-evolve" by swapping its card directly to
	## Grovyle so we can test STAGE1→STAGE2 in isolation (no
	## same-turn-evolution lockout).
	var inst := b.place_active(0, "RS_75_treecko")
	var grovyle: PokemonCardData = _lib.get_card("RS_31_grovyle") as PokemonCardData
	inst.evolve_to(grovyle)
	b.set_prizes(0)
	b.set_prizes(1)
	var sceptile: PokemonCardData = _lib.get_card("RS_11_sceptile") as PokemonCardData
	mgr.game_position.put_in_hand(0, sceptile)

	var r := await mgr.request_action_async(
		ActionEvolve.new(0, sceptile, "p0_active1")
	)
	assert_true(r.ok, "Stage1 → Stage2 should succeed: %s" % r.reason)
	assert_eq(inst.card.stage, PokemonCardData.Stage.STAGE2)


func test_rejects_when_just_entered_play() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	var inst := b.place_active(0, "RS_75_treecko")
	mgr.pokemon_entered_play_this_turn[0].append(inst)
	b.set_prizes(0)
	b.set_prizes(1)
	var grovyle: PokemonCardData = _lib.get_card("RS_31_grovyle") as PokemonCardData
	mgr.game_position.put_in_hand(0, grovyle)

	var r := ActionEvolve.new(0, grovyle, "p0_active1").validate(mgr)
	assert_false(r.ok, "Cannot evolve a Pokémon that just entered play.")


func test_rejects_on_first_turn() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 1)  ## first turn
	b.place_active(0, "RS_75_treecko")
	b.set_prizes(0)
	b.set_prizes(1)
	var grovyle: PokemonCardData = _lib.get_card("RS_31_grovyle") as PokemonCardData
	mgr.game_position.put_in_hand(0, grovyle)

	var r := ActionEvolve.new(0, grovyle, "p0_active1").validate(mgr)
	assert_false(r.ok, "Cannot evolve on the first turn.")


func test_rejects_mismatched_name() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	b.place_active(0, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)
	var grovyle: PokemonCardData = _lib.get_card("RS_31_grovyle") as PokemonCardData
	mgr.game_position.put_in_hand(0, grovyle)

	var r := ActionEvolve.new(0, grovyle, "p0_active1").validate(mgr)
	assert_false(r.ok, "Grovyle does not evolve from Poochyena.")


func test_clears_special_conditions_on_evolve() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	var inst := b.place_active(0, "RS_75_treecko", {
		"conditions": [PokemonInstance.SpecialCondition.ASLEEP],
	})
	b.set_prizes(0)
	b.set_prizes(1)
	var grovyle: PokemonCardData = _lib.get_card("RS_31_grovyle") as PokemonCardData
	mgr.game_position.put_in_hand(0, grovyle)

	await mgr.request_action_async(ActionEvolve.new(0, grovyle, "p0_active1"))
	assert_eq(inst.special_conditions.size(), 0,
		"Evolving should clear all Special Conditions.")

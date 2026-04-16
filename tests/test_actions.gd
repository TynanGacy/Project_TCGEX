extends GutTest

var state: GameState


func before_each() -> void:
	state = GameState.new(2, 1, 5)


func test_advance_phase_from_start() -> void:
	var action := ActionAdvancePhase.new(0)
	var result := action.validate(state)
	assert_true(result.ok)
	action.apply(state)
	assert_eq(state.phase, TurnPhase.Phase.MAIN)


func test_advance_phase_from_end_fails() -> void:
	state.phase = TurnPhase.Phase.END
	var action := ActionAdvancePhase.new(0)
	var result := action.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "END")


func test_end_turn_during_end_phase() -> void:
	state.phase = TurnPhase.Phase.END
	var action := ActionEndTurn.new(0)
	var result := action.validate(state)
	assert_true(result.ok)
	action.apply(state)
	assert_eq(state.current_player_id, 1)


func test_end_turn_during_main_phase_fails() -> void:
	state.phase = TurnPhase.Phase.MAIN
	var action := ActionEndTurn.new(0)
	var result := action.validate(state)
	assert_false(result.ok)


func test_promote_from_bench() -> void:
	var data := CardData.new()
	data.card_id = "BENCH_MON"
	var card := CardInstance.create(data)
	state.board.move_card(card, "p0_bench")
	state.phase = TurnPhase.Phase.MAIN

	var action := ActionPromoteFromBench.new(0, 0, 0)
	var result := action.validate(state)
	assert_true(result.ok)
	action.apply(state)

	var active := state.board.get_active_card(0, 0)
	assert_eq(active, card)


func test_retreat_swaps_active_with_bench_and_discards_energy() -> void:
	state.phase = TurnPhase.Phase.MAIN
	var active := _make_basic_pokemon("active_mon", 1)
	var bench := _make_basic_pokemon("bench_mon", 1)
	var energy := _make_basic_energy("retreat_energy")
	state.board.move_card(active, "p0_active_0")
	state.board.move_card(bench, "p0_bench")
	state.board.move_card(energy, "p0_hand")
	active.attached_energy.append(energy)

	var action := ActionRetreat.new(0, 0, 0)
	var result := action.validate(state)
	assert_true(result.ok, result.reason)
	action.apply(state)

	assert_eq(state.board.get_active_card(0, 0), bench)
	assert_eq(state.board.get_bench_card_at(0, 0), active)
	assert_eq(state.board.find_card_location(energy), "p0_discard")
	assert_true(state.has_retreated_this_turn)


func test_retreat_requires_enough_energy() -> void:
	state.phase = TurnPhase.Phase.MAIN
	var active := _make_basic_pokemon("active_mon", 2)
	var bench := _make_basic_pokemon("bench_mon", 1)
	state.board.move_card(active, "p0_active_0")
	state.board.move_card(bench, "p0_bench")

	var action := ActionRetreat.new(0, 0, 0)
	var result := action.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "Not enough Energy")


func _make_basic_pokemon(card_id: String, retreat_cost: int) -> CardInstance:
	var data := PokemonCardData.new()
	data.card_id = card_id
	data.display_name = card_id
	data.stage = PokemonCardData.Stage.BASIC
	data.hp_max = 60
	data.retreat_cost = retreat_cost
	return CardInstance.create(data)


func _make_basic_energy(card_id: String) -> CardInstance:
	var data := EnergyCardData.new()
	data.card_id = card_id
	data.display_name = card_id
	data.energy_type = PokemonCardData.EnergyType.COLORLESS
	return CardInstance.create(data)

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

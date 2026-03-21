extends GutTest

var state: GameState


func before_each():
	state = GameState.new(2, 1, 5)


# --- ActionAdvancePhase ---

func test_advance_phase_from_start():
	var action = ActionAdvancePhase.new(0)
	var result = action.validate(state)
	assert_true(result.ok)
	action.apply(state)
	assert_eq(state.phase, TurnPhase.Phase.MAIN)


func test_advance_phase_from_end_fails():
	state.phase = TurnPhase.Phase.END
	var action = ActionAdvancePhase.new(0)
	var result = action.validate(state)
	assert_false(result.ok)
	assert_string_contains(result.reason, "END")


# --- ActionEndTurn ---

func test_end_turn_during_end_phase():
	state.phase = TurnPhase.Phase.END
	var action = ActionEndTurn.new(0)
	var result = action.validate(state)
	assert_true(result.ok)
	action.apply(state)
	assert_eq(state.current_player_id, 1)


func test_end_turn_during_main_phase_fails():
	state.phase = TurnPhase.Phase.MAIN
	var action = ActionEndTurn.new(0)
	var result = action.validate(state)
	assert_false(result.ok)


# --- ActionPromoteFromBench ---

func test_promote_from_bench():
	var data = CardData.new()
	data.card_id = "BENCH_MON"
	var card = CardInstance.create(data)
	state.board.move_card(card, "p0_bench")
	state.phase = TurnPhase.Phase.MAIN

	var action = ActionPromoteFromBench.new(0, 0, 0)
	var result = action.validate(state)
	assert_true(result.ok)
	action.apply(state)

	var active = state.board.get_active_card(0, 0)
	assert_eq(active, card)

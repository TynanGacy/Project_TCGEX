extends GutTest

var state: GameState


func before_each():
	state = GameState.new(2, 1, 5)


func test_initial_state():
	assert_eq(state.current_player_id, 0)
	assert_eq(state.turn_number, 1)
	assert_eq(state.phase, TurnPhase.Phase.START)
	assert_eq(state.players.size(), 2)


func test_advance_phase_start_to_main():
	state.advance_phase()
	assert_eq(state.phase, TurnPhase.Phase.MAIN)


func test_advance_phase_full_cycle():
	state.advance_phase()  # START -> MAIN
	assert_eq(state.phase, TurnPhase.Phase.MAIN)
	state.advance_phase()  # MAIN -> ATTACK
	assert_eq(state.phase, TurnPhase.Phase.ATTACK)
	state.advance_phase()  # ATTACK -> END
	assert_eq(state.phase, TurnPhase.Phase.END)
	state.advance_phase()  # END -> stays END
	assert_eq(state.phase, TurnPhase.Phase.END)


func test_end_turn_switches_player():
	state.end_turn()
	assert_eq(state.current_player_id, 1)
	assert_eq(state.turn_number, 2)
	assert_eq(state.phase, TurnPhase.Phase.START)


func test_end_turn_cycles_back_to_player_0():
	state.end_turn()
	state.end_turn()
	assert_eq(state.current_player_id, 0)
	assert_eq(state.turn_number, 3)


func test_begin_turn_resets_flags():
	state.has_attacked_this_turn = true
	state.begin_turn(0)
	assert_false(state.has_attacked_this_turn)


func test_get_current_player():
	var player = state.get_current_player()
	assert_not_null(player)
	assert_eq(player.player_id, 0)


func test_get_player_by_id():
	var p1 = state.get_player(1)
	assert_not_null(p1)
	assert_eq(p1.player_id, 1)


func test_get_player_invalid_id():
	var p = state.get_player(5)
	assert_null(p)

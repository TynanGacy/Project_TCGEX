extends GutTest

var state: GameState


func before_each() -> void:
	state = GameState.new(2, 1, 5)


func _make_card_data(id: String) -> CardData:
	var data := CardData.new()
	data.card_id = id
	data.display_name = id
	return data


func _make_deck(size: int) -> Array[CardData]:
	var deck: Array[CardData] = []
	for i in size:
		deck.append(_make_card_data("CARD_%d" % i))
	return deck


# --- Deck population ---

func test_setup_deck_populates_board_zone() -> void:
	state.setup_player_deck(0, _make_deck(10))
	assert_eq(state.board.count_cards_in_zone("p0_deck"), 10)


func test_setup_deck_cards_have_deck_zone_enum() -> void:
	state.setup_player_deck(0, _make_deck(5))
	for card in state.board.get_zone("p0_deck"):
		assert_eq((card as CardInstance).zone, CardInstance.Zone.DECK)


func test_setup_deck_assigns_owner() -> void:
	state.setup_player_deck(1, _make_deck(3))
	for card in state.board.get_zone("p1_deck"):
		assert_eq((card as CardInstance).owner_id, 1)


func test_setup_deck_does_not_cross_contaminate_players() -> void:
	state.setup_player_deck(0, _make_deck(5))
	assert_eq(state.board.count_cards_in_zone("p1_deck"), 0)


# --- Starting hand ---

func test_draw_starting_hand_moves_cards_to_hand() -> void:
	state.setup_player_deck(0, _make_deck(60))
	state.draw_starting_hand(0, 7)
	assert_eq(state.board.count_cards_in_zone("p0_hand"), 7)
	assert_eq(state.board.count_cards_in_zone("p0_deck"), 13)


func test_draw_starting_hand_updates_zone_enum() -> void:
	state.setup_player_deck(0, _make_deck(10))
	state.draw_starting_hand(0, 5)
	for card in state.board.get_hand_cards(0):
		assert_eq(card.zone, CardInstance.Zone.HAND)


func test_draw_starting_hand_capped_by_deck_size() -> void:
	state.setup_player_deck(0, _make_deck(3))
	state.draw_starting_hand(0, 7)
	assert_eq(state.board.count_cards_in_zone("p0_hand"), 3)
	assert_eq(state.board.count_cards_in_zone("p0_deck"), 0)


# --- ActionDrawCard ---

func test_action_draw_card_succeeds_when_deck_has_cards() -> void:
	state.setup_player_deck(0, _make_deck(10))
	var action := ActionDrawCard.new(0, 1)
	assert_true(action.validate(state).ok)


func test_action_draw_card_fails_on_empty_deck() -> void:
	var action := ActionDrawCard.new(0, 1)
	var result := action.validate(state)
	assert_false(result.ok)
	assert_ne(result.reason, "")


func test_action_draw_card_moves_card_to_hand() -> void:
	state.setup_player_deck(0, _make_deck(10))
	var action := ActionDrawCard.new(0, 1)
	action.apply(state)
	assert_eq(state.board.count_cards_in_zone("p0_hand"), 1)
	assert_eq(state.board.count_cards_in_zone("p0_deck"), 9)


func test_action_draw_card_draws_multiple() -> void:
	state.setup_player_deck(0, _make_deck(10))
	var action := ActionDrawCard.new(0, 3)
	action.apply(state)
	assert_eq(state.board.count_cards_in_zone("p0_hand"), 3)
	assert_eq(state.board.count_cards_in_zone("p0_deck"), 7)


func test_action_draw_card_stops_at_empty_deck() -> void:
	state.setup_player_deck(0, _make_deck(2))
	var action := ActionDrawCard.new(0, 5)
	action.apply(state)
	assert_eq(state.board.count_cards_in_zone("p0_hand"), 2)
	assert_eq(state.board.count_cards_in_zone("p0_deck"), 0)


# --- ActionDiscardCard ---

func test_action_discard_from_hand_succeeds() -> void:
	state.setup_player_deck(0, _make_deck(5))
	state.draw_starting_hand(0, 1)
	var card := state.board.get_hand_cards(0)[0]
	var action := ActionDiscardCard.new(0, card)
	assert_true(action.validate(state).ok)


func test_action_discard_from_hand_moves_to_discard() -> void:
	state.setup_player_deck(0, _make_deck(5))
	state.draw_starting_hand(0, 1)
	var card := state.board.get_hand_cards(0)[0]
	ActionDiscardCard.new(0, card).apply(state)
	assert_eq(state.board.count_cards_in_zone("p0_hand"), 0)
	assert_eq(state.board.count_cards_in_zone("p0_discard"), 1)
	assert_eq(card.zone, CardInstance.Zone.DISCARD)


func test_action_discard_from_bench_moves_to_discard() -> void:
	state.setup_player_deck(0, _make_deck(5))
	state.draw_starting_hand(0, 1)
	var card := state.board.get_hand_cards(0)[0]
	state.board.move_card(card, "p0_bench")
	ActionDiscardCard.new(0, card).apply(state)
	assert_eq(state.board.count_cards_in_zone("p0_bench"), 0)
	assert_eq(state.board.count_cards_in_zone("p0_discard"), 1)


func test_action_discard_null_card_fails() -> void:
	var result := ActionDiscardCard.new(0, null).validate(state)
	assert_false(result.ok)


func test_action_discard_card_not_in_play_fails() -> void:
	var card := CardInstance.create(_make_card_data("GHOST"))
	card.controller_id = 0
	var result := ActionDiscardCard.new(0, card).validate(state)
	assert_false(result.ok)


func test_action_discard_opponent_card_fails() -> void:
	state.setup_player_deck(1, _make_deck(5))
	state.draw_starting_hand(1, 1)
	var opponent_card := state.board.get_hand_cards(1)[0]
	var result := ActionDiscardCard.new(0, opponent_card).validate(state)
	assert_false(result.ok)

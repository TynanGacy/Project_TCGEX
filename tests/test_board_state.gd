extends GutTest

var board: BoardState
var card_a: CardInstance
var card_b: CardInstance


func before_each():
	board = BoardState.new(2, 1, 5)

	var data_a = CardData.new()
	data_a.card_id = "TEST_A"
	data_a.display_name = "Test Card A"
	card_a = CardInstance.create(data_a)

	var data_b = CardData.new()
	data_b.card_id = "TEST_B"
	data_b.display_name = "Test Card B"
	card_b = CardInstance.create(data_b)


func test_zones_created():
	assert_true(board.zones.has("p0_hand"))
	assert_true(board.zones.has("p1_hand"))
	assert_true(board.zones.has("p0_active_0"))
	assert_true(board.zones.has("p1_bench"))
	assert_true(board.zones.has("stadium"))


func test_move_card_to_hand():
	board.move_card(card_a, "p0_hand")
	var hand = board.get_zone("p0_hand")
	assert_eq(hand.size(), 1)
	assert_eq(hand[0], card_a)


func test_move_card_between_zones():
	board.move_card(card_a, "p0_hand")
	board.move_card(card_a, "p0_bench")
	assert_eq(board.get_zone("p0_hand").size(), 0)
	assert_eq(board.get_zone("p0_bench").size(), 1)


func test_get_active_card():
	board.move_card(card_a, "p0_active_0")
	var active = board.get_active_card(0, 0)
	assert_eq(active, card_a)


func test_get_active_card_empty():
	var active = board.get_active_card(0, 0)
	assert_null(active)


func test_get_first_empty_active_slot():
	var slot = board.get_first_empty_active_slot(0)
	assert_eq(slot, 0)

	board.move_card(card_a, "p0_active_0")
	slot = board.get_first_empty_active_slot(0)
	assert_eq(slot, -1)


func test_swap_cards():
	board.move_card(card_a, "p0_active_0")
	board.move_card(card_b, "p0_bench")
	board.swap_cards(card_a, card_b)

	assert_eq(board.get_zone("p0_bench")[0], card_a)
	assert_eq(board.get_zone("p0_active_0")[0], card_b)

class_name Player
extends RefCounted

signal deck_empty
signal prize_taken(remaining: int)
signal deck_shuffled

var player_id: int = 0
var player_name: String = "Player"

var deck_list: Array[CardData] = []
var prizes_remaining: int = 6

var has_attached_energy_this_turn: bool = false
var supporter_played_this_turn: bool = false
var stadium_played_this_turn: bool = false


func _init(id: int = 0, pname: String = "") -> void:
	player_id = id
	if pname != "":
		player_name = pname
	else:
		player_name = "Player %d" % (id + 1)


func setup_deck(card_data_array: Array[CardData]) -> void:
	deck_list.clear()
	deck_list.assign(card_data_array)


func load_deck_into_board(board: BoardState) -> Array[CardInstance]:
	var instances: Array[CardInstance] = []
	var deck_zone_id := "p%d_deck" % player_id

	for data in deck_list:
		var inst := CardInstance.create(data)
		inst.owner_id = player_id
		inst.controller_id = player_id
		board.move_card(inst, deck_zone_id)
		instances.append(inst)

	return instances


func shuffle_deck_zone(board: BoardState) -> void:
	var deck_zone_id := "p%d_deck" % player_id
	var deck_cards := board.get_zone(deck_zone_id)

	if deck_cards.is_empty():
		return

	for i in range(deck_cards.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var temp: Variant = deck_cards[i]
		deck_cards[i] = deck_cards[j]
		deck_cards[j] = temp

	deck_shuffled.emit()


func draw_card(board: BoardState) -> CardInstance:
	var deck_zone_id := "p%d_deck" % player_id
	var deck_cards := board.get_zone(deck_zone_id)

	if deck_cards.is_empty():
		deck_empty.emit()
		return null

	var card: CardInstance = deck_cards.back()
	board.move_card(card, "p%d_hand" % player_id)
	return card


func take_prize_card(board: BoardState) -> CardInstance:
	var prizes_zone_id := "p%d_prizes" % player_id
	var prize_cards := board.get_zone(prizes_zone_id)

	if prize_cards.is_empty():
		return null

	var card: CardInstance = prize_cards.pop_back()
	prizes_remaining = prize_cards.size()

	prize_taken.emit(prizes_remaining)

	return card


func reset_turn_flags() -> void:
	has_attached_energy_this_turn = false
	supporter_played_this_turn = false
	stadium_played_this_turn = false


func can_attach_energy() -> bool:
	return not has_attached_energy_this_turn


func can_play_supporter() -> bool:
	return not supporter_played_this_turn


func can_play_stadium() -> bool:
	return not stadium_played_this_turn


func mark_energy_attached() -> void:
	has_attached_energy_this_turn = true


func mark_supporter_played() -> void:
	supporter_played_this_turn = true


func mark_stadium_played() -> void:
	stadium_played_this_turn = true

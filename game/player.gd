# res://game/player.gd
class_name Player
extends RefCounted

## Player represents one player in the game.
## It manages their deck, prizes, and turn-based restrictions.

# ============================================================
#	Signals
# ============================================================
signal deck_empty
signal prize_taken(remaining: int)
signal deck_shuffled


# ============================================================
#	Identity
# ============================================================
var player_id: int = 0
var player_name: String = "Player"


# ============================================================
#	Deck & Prizes (stored separately from BoardState zones)
# ============================================================
var deck_list: Array[CardData] = []  # Original deck definition
var prizes_remaining: int = 6


# ============================================================
#	Turn State Flags
# ============================================================
var has_attached_energy_this_turn: bool = false
var supporter_played_this_turn: bool = false
var stadium_played_this_turn: bool = false


# ============================================================
#	Initialization
# ============================================================
func _init(id: int = 0, name: String = "") -> void:
	player_id = id
	if name != "":
		player_name = name
	else:
		player_name = "Player %d" % (id + 1)


func setup_deck(card_data_array: Array[CardData]) -> void:
	"""Sets up this player's deck from an array of CardData.
	Creates CardInstances and places them in the deck zone via BoardState."""
	deck_list.clear()
	deck_list.assign(card_data_array)


func load_deck_into_board(board: BoardState) -> Array[CardInstance]:
	"""Creates CardInstances from deck_list and returns them.
	Caller should then move them to the appropriate deck zone."""
	var instances: Array[CardInstance] = []
	
	for data in deck_list:
		var inst := CardInstance.create(data)
		inst.owner_id = player_id
		inst.controller_id = player_id
		inst.zone = CardInstance.Zone.DECK
		instances.append(inst)
	
	return instances


func shuffle_deck_zone(board: BoardState) -> void:
	"""Shuffles the cards in this player's deck zone."""
	var deck_zone_id := "p%d_deck" % player_id
	var deck_cards := board.get_zone(deck_zone_id)
	
	if deck_cards.is_empty():
		return
	
	# Fisher-Yates shuffle
	for i in range(deck_cards.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var temp = deck_cards[i]
		deck_cards[i] = deck_cards[j]
		deck_cards[j] = temp
	
	deck_shuffled.emit()


func draw_card(board: BoardState) -> CardInstance:
	"""Draws the top card from this player's deck zone.
	Returns null if deck is empty."""
	var deck_zone_id := "p%d_deck" % player_id
	var deck_cards := board.get_zone(deck_zone_id)
	
	if deck_cards.is_empty():
		deck_empty.emit()
		return null
	
	# Take from the end (top of deck)
	var card: CardInstance = deck_cards.pop_back()
	return card


func take_prize_card(board: BoardState) -> CardInstance:
	"""Takes a prize card and moves it to hand.
	Returns the card, or null if no prizes left."""
	var prizes_zone_id := "p%d_prizes" % player_id
	var prize_cards := board.get_zone(prizes_zone_id)
	
	if prize_cards.is_empty():
		return null
	
	var card: CardInstance = prize_cards.pop_back()
	prizes_remaining = prize_cards.size()
	
	prize_taken.emit(prizes_remaining)
	
	return card


# ============================================================
#	Turn Management
# ============================================================
func reset_turn_flags() -> void:
	"""Called at the start of this player's turn."""
	has_attached_energy_this_turn = false
	supporter_played_this_turn = false
	stadium_played_this_turn = false


func can_attach_energy() -> bool:
	"""Checks if this player can attach an energy this turn."""
	return not has_attached_energy_this_turn


func can_play_supporter() -> bool:
	"""Checks if this player can play a Supporter this turn."""
	return not supporter_played_this_turn


func can_play_stadium() -> bool:
	"""Checks if this player can play a Stadium this turn.
	(In official rules, you can only play 1 Stadium per turn)"""
	return not stadium_played_this_turn


func mark_energy_attached() -> void:
	"""Marks that an energy has been attached this turn."""
	has_attached_energy_this_turn = true


func mark_supporter_played() -> void:
	"""Marks that a Supporter has been played this turn."""
	supporter_played_this_turn = true


func mark_stadium_played() -> void:
	"""Marks that a Stadium has been played this turn."""
	stadium_played_this_turn = true


# ============================================================
#	Win Condition Helpers
# ============================================================
func has_lost_by_prizes() -> bool:
	"""Returns true if this player has no prizes left (they WON actually)."""
	return prizes_remaining <= 0


func has_lost_by_deck_out(board: BoardState) -> bool:
	"""Returns true if player must draw but can't."""
	var deck_zone_id := "p%d_deck" % player_id
	return board.get_zone(deck_zone_id).is_empty()


func has_lost_by_no_pokemon(board: BoardState) -> bool:
	"""Returns true if player has no active Pokemon and no bench."""
	var has_active := false
	for slot_idx in range(board.num_active_slots):
		if board.get_active_card(player_id, slot_idx) != null:
			has_active = true
			break
	
	if has_active:
		return false
	
	# No active, check bench
	return board.get_bench_cards(player_id).is_empty()


# ============================================================
#	Debugging
# ============================================================
func print_player_state(board: BoardState) -> void:
	"""Prints this player's state for debugging."""
	print("=== Player %d (%s) ===" % [player_id, player_name])
	print("  Deck: %d cards" % board.count_cards_in_zone("p%d_deck" % player_id))
	print("  Hand: %d cards" % board.count_cards_in_zone("p%d_hand" % player_id))
	print("  Prizes: %d remaining" % prizes_remaining)
	print("  Active: %d / %d" % [board.count_active_pokemon(player_id), board.num_active_slots])
	print("  Bench: %d / %d" % [board.count_cards_in_zone("p%d_bench" % player_id), board.max_bench_size])
	print("  Energy attached this turn: %s" % has_attached_energy_this_turn)
	print("  Supporter played this turn: %s" % supporter_played_this_turn)

# res://game/board_state.gd
class_name BoardState
extends RefCounted

## BoardState manages the logical state of the game board
## (cards in zones, positions, etc.) separate from UI/rendering.
##
## This class emits signals when things change so the UI can react,
## but it doesn't know anything about Nodes, CardViews, or the scene tree.

# ============================================================
#	Signals
# ============================================================
signal card_moved(card: CardInstance, from_zone_id: String, to_zone_id: String)
signal card_added_to_zone(card: CardInstance, zone_id: String)
signal card_removed_from_zone(card: CardInstance, zone_id: String)


# ============================================================
#	Configuration
# ============================================================
var num_players: int = 2
var max_bench_size: int = 5
var num_active_slots: int = 1
var max_prizes: int = 6


# ============================================================
#	Zone Storage
#	Each zone is identified by a string like "p0_hand", "p1_bench", etc.
# ============================================================
var zones: Dictionary = {}


# ============================================================
#	Initialization
# ============================================================
func _init(players: int = 2, active_slots: int = 1, bench_size: int = 5) -> void:
	num_players = players
	num_active_slots = active_slots
	max_bench_size = bench_size
	setup_zones()


func setup_zones() -> void:
	"""Create all the zone arrays for each player."""
	zones.clear()
	
	for player_id in range(num_players):
		zones["p%d_hand" % player_id] = []
		zones["p%d_deck" % player_id] = []
		zones["p%d_discard" % player_id] = []
		zones["p%d_prizes" % player_id] = []
		zones["p%d_bench" % player_id] = []
		
		# Active slots (can be multiple for doubles format)
		for slot_idx in range(num_active_slots):
			zones["p%d_active_%d" % [player_id, slot_idx]] = []
	
	# Shared zones
	zones["stadium"] = []


# ============================================================
#	Zone Queries
# ============================================================
func get_zone(zone_id: String) -> Array:
	"""Returns the array of CardInstances in the specified zone.
	Returns empty array if zone doesn't exist."""
	return zones.get(zone_id, [])


func get_all_zone_ids() -> Array:
	"""Returns all zone ID strings."""
	return zones.keys()


func get_player_zone_ids(player_id: int) -> Array:
	"""Returns all zone IDs belonging to a specific player."""
	var result: Array = []
	for zone_id in zones.keys():
		if zone_id.begins_with("p%d_" % player_id):
			result.append(zone_id)
	return result


func find_card_location(card: CardInstance) -> String:
	"""Searches all zones and returns the zone_id where this card is located.
	Returns empty string if not found."""
	for zone_id in zones.keys():
		var zone_array: Array = zones[zone_id]
		if zone_array.has(card):
			return zone_id
	return ""


func count_cards_in_zone(zone_id: String) -> int:
	"""Returns number of cards in the specified zone."""
	return get_zone(zone_id).size()


# ============================================================
#	Zone Capacity Checks
# ============================================================
func can_add_to_zone(zone_id: String, card: CardInstance = null) -> bool:
	"""Checks if a card can be added to the specified zone.
	Returns false if zone is full or doesn't exist."""
	
	if not zones.has(zone_id):
		return false
	
	var zone_array: Array = get_zone(zone_id)
	
	# Bench has size limits
	if "bench" in zone_id:
		return zone_array.size() < max_bench_size
	
	# Active slots can only hold 1 card each
	if "active" in zone_id:
		return zone_array.size() == 0
	
	# Most other zones have no limit (hand, deck, discard)
	return true


func get_first_empty_active_slot(player_id: int) -> int:
	"""Returns the index of the first empty active slot for a player.
	Returns -1 if all slots are full."""
	for slot_idx in range(num_active_slots):
		var zone_id := "p%d_active_%d" % [player_id, slot_idx]
		if get_zone(zone_id).is_empty():
			return slot_idx
	return -1


# ============================================================
#	Card Movement (Core Logic)
# ============================================================
func move_card(card: CardInstance, to_zone_id: String) -> bool:
	"""Moves a card from wherever it currently is to the target zone.
	Returns true on success, false if the move is invalid."""
	
	if card == null:
		push_error("move_card: card is null")
		return false
	
	if not zones.has(to_zone_id):
		push_error("move_card: zone '%s' does not exist" % to_zone_id)
		return false
	
	# Check capacity
	if not can_add_to_zone(to_zone_id, card):
		return false
	
	# Find current location
	var from_zone_id := find_card_location(card)
	
	# Remove from old zone if it exists
	if from_zone_id != "":
		var from_array: Array = zones[from_zone_id]
		from_array.erase(card)
		card_removed_from_zone.emit(card, from_zone_id)
	
	# Add to new zone
	var to_array: Array = zones[to_zone_id]
	to_array.append(card)
	
	# Update CardInstance's zone enum
	card.zone = _zone_id_to_enum(to_zone_id)
	
	card_added_to_zone.emit(card, to_zone_id)
	
	if from_zone_id != "":
		card_moved.emit(card, from_zone_id, to_zone_id)
	
	return true


func move_card_to_position(card: CardInstance, to_zone_id: String, position: int) -> bool:
	"""Moves a card to a specific position in the target zone (e.g., deck order).
	Returns true on success."""
	
	if card == null or not zones.has(to_zone_id):
		return false
	
	if not can_add_to_zone(to_zone_id, card):
		return false
	
	# Remove from current location
	var from_zone_id := find_card_location(card)
	if from_zone_id != "":
		var from_array: Array = zones[from_zone_id]
		from_array.erase(card)
		card_removed_from_zone.emit(card, from_zone_id)
	
	# Add to new zone at specific position
	var to_array: Array = zones[to_zone_id]
	var clamped_pos := clampi(position, 0, to_array.size())
	to_array.insert(clamped_pos, card)
	
	card.zone = _zone_id_to_enum(to_zone_id)
	
	card_added_to_zone.emit(card, to_zone_id)
	if from_zone_id != "":
		card_moved.emit(card, from_zone_id, to_zone_id)
	
	return true


func swap_cards(card_a: CardInstance, card_b: CardInstance) -> bool:
	"""Swaps the positions of two cards (typically active <-> bench).
	Returns true on success."""
	
	if card_a == null or card_b == null:
		return false
	
	var zone_a := find_card_location(card_a)
	var zone_b := find_card_location(card_b)
	
	if zone_a == "" or zone_b == "":
		return false
	
	# Remove both from their zones
	var array_a: Array = zones[zone_a]
	var array_b: Array = zones[zone_b]
	
	var index_a := array_a.find(card_a)
	var index_b := array_b.find(card_b)
	
	array_a.erase(card_a)
	array_b.erase(card_b)
	
	# Add to opposite zones, preserving index if same zone
	if zone_a == zone_b:
		# Swapping within same zone
		array_a.insert(index_b, card_a)
		array_a.insert(index_a, card_b)
	else:
		# Swapping between different zones
		array_b.append(card_a)
		array_a.append(card_b)
	
	# Update zone enums
	card_a.zone = _zone_id_to_enum(zone_b)
	card_b.zone = _zone_id_to_enum(zone_a)
	
	# Emit signals
	card_moved.emit(card_a, zone_a, zone_b)
	card_moved.emit(card_b, zone_b, zone_a)
	
	return true


func remove_card(card: CardInstance) -> bool:
	"""Removes a card from whatever zone it's in.
	Returns true if found and removed."""
	
	var zone_id := find_card_location(card)
	if zone_id == "":
		return false
	
	var zone_array: Array = zones[zone_id]
	zone_array.erase(card)
	card.zone = CardInstance.Zone.OTHER
	
	card_removed_from_zone.emit(card, zone_id)
	
	return true


# ============================================================
#	Helper: Zone ID to CardInstance.Zone enum
# ============================================================
func _zone_id_to_enum(zone_id: String) -> CardInstance.Zone:
	"""Converts a zone_id string to the CardInstance.Zone enum."""
	if "hand" in zone_id:
		return CardInstance.Zone.HAND
	elif "deck" in zone_id:
		return CardInstance.Zone.DECK
	elif "active" in zone_id:
		return CardInstance.Zone.ACTIVE
	elif "bench" in zone_id:
		return CardInstance.Zone.BENCH
	elif "discard" in zone_id:
		return CardInstance.Zone.DISCARD
	elif "prizes" in zone_id:
		return CardInstance.Zone.PRIZES
	else:
		return CardInstance.Zone.OTHER


# ============================================================
#	High-Level Game Queries
# ============================================================
func get_active_card(player_id: int, slot_index: int) -> CardInstance:
	"""Returns the card in the specified active slot, or null if empty."""
	var zone_id := "p%d_active_%d" % [player_id, slot_index]
	var zone_array := get_zone(zone_id)
	
	if zone_array.is_empty():
		return null
	
	return zone_array[0] as CardInstance


func get_bench_cards(player_id: int) -> Array[CardInstance]:
	"""Returns all cards on a player's bench."""
	var zone_id := "p%d_bench" % player_id
	var result: Array[CardInstance] = []
	for card in get_zone(zone_id):
		if card is CardInstance:
			result.append(card)
	return result


func get_bench_card_at(player_id: int, bench_index: int) -> CardInstance:
	"""Returns the card at a specific bench position, or null if invalid."""
	var bench_cards := get_bench_cards(player_id)
	if bench_index >= 0 and bench_index < bench_cards.size():
		return bench_cards[bench_index]
	return null


func get_hand_cards(player_id: int) -> Array[CardInstance]:
	"""Returns all cards in a player's hand."""
	var zone_id := "p%d_hand" % player_id
	var result: Array[CardInstance] = []
	for card in get_zone(zone_id):
		if card is CardInstance:
			result.append(card)
	return result


func count_active_pokemon(player_id: int) -> int:
	"""Returns the number of active slots that have a Pokemon."""
	var count := 0
	for slot_idx in range(num_active_slots):
		if get_active_card(player_id, slot_idx) != null:
			count += 1
	return count


# ============================================================
#	Validation Helpers (for Actions)
# ============================================================
func can_play_card_to_bench(player_id: int) -> bool:
	"""Checks if a player can add a card to their bench."""
	var zone_id := "p%d_bench" % player_id
	return can_add_to_zone(zone_id)


func can_play_card_to_active(player_id: int) -> bool:
	"""Checks if a player has an empty active slot."""
	return get_first_empty_active_slot(player_id) != -1


func can_swap_active_with_bench(player_id: int, active_slot: int, bench_index: int) -> bool:
	"""Validates a swap between active and bench."""
	var active_card := get_active_card(player_id, active_slot)
	if active_card == null:
		return false
	
	var bench_card := get_bench_card_at(player_id, bench_index)
	if bench_card == null:
		return false
	
	return true


# ============================================================
#	Debug / Utility
# ============================================================
func print_board_state() -> void:
	"""Prints the current state of all zones for debugging."""
	print("=== Board State ===")
	for zone_id in zones.keys():
		var zone_array: Array = zones[zone_id]
		if zone_array.is_empty():
			continue
		print("  %s: %d cards" % [zone_id, zone_array.size()])
		for card in zone_array:
			if card is CardInstance:
				print("    - %s (ID: %d)" % [card.data.display_name, card.instance_id])

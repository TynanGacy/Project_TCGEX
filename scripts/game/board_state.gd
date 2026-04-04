class_name BoardState
extends RefCounted

signal card_moved(card: CardInstance, from_zone_id: String, to_zone_id: String)
signal card_added_to_zone(card: CardInstance, zone_id: String)
signal card_removed_from_zone(card: CardInstance, zone_id: String)

var num_players: int = 2
var max_bench_size: int = 5
var num_active_slots: int = 1
var max_prizes: int = 6

var zones: Dictionary = {}


func _init(players: int = 2, active_slots: int = 1, bench_size: int = 5) -> void:
	num_players = players
	num_active_slots = active_slots
	max_bench_size = bench_size
	setup_zones()


func setup_zones() -> void:
	zones.clear()

	for player_id in range(num_players):
		zones["p%d_hand" % player_id] = []
		zones["p%d_deck" % player_id] = []
		zones["p%d_discard" % player_id] = []
		zones["p%d_prizes" % player_id] = []
		zones["p%d_bench" % player_id] = []

		for slot_idx in range(num_active_slots):
			zones["p%d_active_%d" % [player_id, slot_idx]] = []

	zones["stadium"] = []


func get_zone(zone_id: String) -> Array:
	return zones.get(zone_id, [])


func get_all_zone_ids() -> Array:
	return zones.keys()


func get_player_zone_ids(player_id: int) -> Array:
	var result: Array = []
	for zone_id in zones.keys():
		if zone_id.begins_with("p%d_" % player_id):
			result.append(zone_id)
	return result


func find_card_location(card: CardInstance) -> String:
	for zone_id in zones.keys():
		var zone_array: Array = zones[zone_id]
		if zone_array.has(card):
			return zone_id
	return ""


func count_cards_in_zone(zone_id: String) -> int:
	return get_zone(zone_id).size()


func can_add_to_zone(zone_id: String, _card: CardInstance = null) -> bool:
	if not zones.has(zone_id):
		return false

	var zone_array: Array = get_zone(zone_id)

	if "bench" in zone_id:
		return zone_array.size() < max_bench_size

	if "active" in zone_id:
		return zone_array.size() == 0

	return true


func get_first_empty_active_slot(player_id: int) -> int:
	for slot_idx in range(num_active_slots):
		var zone_id := "p%d_active_%d" % [player_id, slot_idx]
		if get_zone(zone_id).is_empty():
			return slot_idx
	return -1


func move_card(card: CardInstance, to_zone_id: String) -> bool:
	if card == null:
		push_error("move_card: card is null")
		return false

	if not zones.has(to_zone_id):
		push_error("move_card: zone '%s' does not exist" % to_zone_id)
		return false

	if not can_add_to_zone(to_zone_id, card):
		return false

	var from_zone_id := find_card_location(card)

	if from_zone_id != "":
		var from_array: Array = zones[from_zone_id]
		from_array.erase(card)
		card_removed_from_zone.emit(card, from_zone_id)

	var to_array: Array = zones[to_zone_id]
	to_array.append(card)

	card.zone = _zone_id_to_enum(to_zone_id)

	card_added_to_zone.emit(card, to_zone_id)

	if from_zone_id != "":
		card_moved.emit(card, from_zone_id, to_zone_id)

	return true


func move_card_to_position(card: CardInstance, to_zone_id: String, pos: int) -> bool:
	if card == null or not zones.has(to_zone_id):
		return false

	if not can_add_to_zone(to_zone_id, card):
		return false

	var from_zone_id := find_card_location(card)
	if from_zone_id != "":
		var from_array: Array = zones[from_zone_id]
		from_array.erase(card)
		card_removed_from_zone.emit(card, from_zone_id)

	var to_array: Array = zones[to_zone_id]
	var clamped_pos := clampi(pos, 0, to_array.size())
	to_array.insert(clamped_pos, card)

	card.zone = _zone_id_to_enum(to_zone_id)

	card_added_to_zone.emit(card, to_zone_id)
	if from_zone_id != "":
		card_moved.emit(card, from_zone_id, to_zone_id)

	return true


func swap_cards(card_a: CardInstance, card_b: CardInstance) -> bool:
	if card_a == null or card_b == null:
		return false

	var zone_a := find_card_location(card_a)
	var zone_b := find_card_location(card_b)

	if zone_a == "" or zone_b == "":
		return false

	var array_a: Array = zones[zone_a]
	var array_b: Array = zones[zone_b]

	var index_a := array_a.find(card_a)
	var index_b := array_b.find(card_b)

	if zone_a == zone_b:
		# In-place swap by index: no erase so positions stay valid.
		array_a[index_a] = card_b
		array_a[index_b] = card_a
	else:
		array_a.erase(card_a)
		array_b.erase(card_b)
		array_b.append(card_a)
		array_a.append(card_b)

	card_a.zone = _zone_id_to_enum(zone_b)
	card_b.zone = _zone_id_to_enum(zone_a)

	card_moved.emit(card_a, zone_a, zone_b)
	card_moved.emit(card_b, zone_b, zone_a)

	return true


func remove_card(card: CardInstance) -> bool:
	var zone_id := find_card_location(card)
	if zone_id == "":
		return false

	var zone_array: Array = zones[zone_id]
	zone_array.erase(card)
	card.zone = CardInstance.Zone.OTHER

	card_removed_from_zone.emit(card, zone_id)

	return true


## Maps a zone_id string to the CardInstance.Zone enum used for per-card state.
## "stadium" contains none of the keywords below, so it correctly falls through
## to OTHER — stadium cards track ownership via owner_id, not the Zone enum.
func _zone_id_to_enum(zone_id: String) -> CardInstance.Zone:
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


func get_active_card(player_id: int, slot_index: int) -> CardInstance:
	var zone_id := "p%d_active_%d" % [player_id, slot_index]
	var zone_array := get_zone(zone_id)

	if zone_array.is_empty():
		return null

	return zone_array[0] as CardInstance


func get_bench_cards(player_id: int) -> Array[CardInstance]:
	var zone_id := "p%d_bench" % player_id
	var result: Array[CardInstance] = []
	for card in get_zone(zone_id):
		if card is CardInstance:
			result.append(card)
	return result


func get_bench_card_at(player_id: int, bench_index: int) -> CardInstance:
	var bench_cards := get_bench_cards(player_id)
	if bench_index >= 0 and bench_index < bench_cards.size():
		return bench_cards[bench_index]
	return null


func get_hand_cards(player_id: int) -> Array[CardInstance]:
	var zone_id := "p%d_hand" % player_id
	var result: Array[CardInstance] = []
	for card in get_zone(zone_id):
		if card is CardInstance:
			result.append(card)
	return result


func count_active_pokemon(player_id: int) -> int:
	var count := 0
	for slot_idx in range(num_active_slots):
		if get_active_card(player_id, slot_idx) != null:
			count += 1
	return count


func can_play_card_to_bench(player_id: int) -> bool:
	var zone_id := "p%d_bench" % player_id
	return can_add_to_zone(zone_id)


func can_play_card_to_active(player_id: int) -> bool:
	return get_first_empty_active_slot(player_id) != -1


func can_swap_active_with_bench(player_id: int, active_slot: int, bench_index: int) -> bool:
	var active_card := get_active_card(player_id, active_slot)
	if active_card == null:
		return false

	var bench_card := get_bench_card_at(player_id, bench_index)
	if bench_card == null:
		return false

	return true

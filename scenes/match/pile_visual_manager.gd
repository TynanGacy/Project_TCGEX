class_name PileVisualManager
extends Node

## Manages deck / discard / prize card visuals on the board.

const DECK_MAX_LAYERS: int = 12
const DECK_LAYER_THICKNESS: float = 0.018
const DECK_FULL_SIZE: int = 60

var _main: Node = null
var _pile_nodes: Dictionary = {}


func init(main_node: Node) -> void:
	_main = main_node


func clear() -> void:
	for entry in _pile_nodes.values():
		if entry is Array:
			for layer in entry:
				if is_instance_valid(layer):
					(layer as Node).queue_free()
		elif is_instance_valid(entry):
			(entry as Node).queue_free()
	_pile_nodes.clear()


func refresh_deck(pid: int) -> void:
	var zone_name := "%sDeck" % MatchUIUtils.zone_prefix(pid)
	var zone: DropZone = (_main.board as Board).get_named_zone(zone_name)
	if zone == null:
		return
	var count: int = (_main.manager.game_position.decks[pid] as Array).size()

	var layers: Array = _pile_nodes.get(zone_name, []) as Array
	for old_layer in layers:
		if is_instance_valid(old_layer):
			(old_layer as Node).queue_free()
	layers.clear()

	if count == 0:
		_pile_nodes.erase(zone_name)
		zone.set_label("Deck (0)")
		return

	var layer_count: int = clampi(
		ceili(float(count) / float(DECK_FULL_SIZE) * DECK_MAX_LAYERS),
		1, DECK_MAX_LAYERS
	)
	for i in range(layer_count):
		var layer_node := _main.card_scene.instantiate() as Card
		zone.add_child(layer_node)
		layer_node.position = Vector3(0, i * DECK_LAYER_THICKNESS, 0)
		layer_node.back_texture = _main.CARD_BACK
		layer_node.face_down = true
		layers.append(layer_node)
	_pile_nodes[zone_name] = layers
	zone.set_label("Deck (%d)" % count)


func refresh_discard(pid: int) -> void:
	var zone_name := "%sDiscard" % MatchUIUtils.zone_prefix(pid)
	var zone: DropZone = (_main.board as Board).get_named_zone(zone_name)
	if zone == null:
		return
	var discard: Array = _main.manager.game_position.discards[pid]
	var node := _pile_nodes.get(zone_name, null) as Card
	if discard.is_empty():
		if node != null:
			node.queue_free()
			_pile_nodes.erase(zone_name)
		zone.set_label("Discard (0)")
		return
	if node == null:
		node = _main.card_scene.instantiate() as Card
		zone.add_child(node)
		node.position = Vector3.ZERO
		if pid == 1:
			node.rotation.y = PI
		_pile_nodes[zone_name] = node
	node.face_down = false
	node.set_data(discard.back() as CardData)
	zone.set_label("Discard (%d)" % discard.size())


func refresh_prizes(pid: int) -> void:
	var prefix := MatchUIUtils.zone_prefix(pid)
	var prize_row: Array = _main.manager.game_position.prizes[pid]
	for i in range(6):
		var zone_name := "%sPrize %d" % [prefix, i + 1]
		var zone: DropZone = (_main.board as Board).get_named_zone(zone_name)
		if zone == null or not zone.visible:
			continue
		var node := _pile_nodes.get(zone_name, null) as Card
		var occupied: bool = (prize_row[i] != null)
		if not occupied:
			if node != null:
				node.queue_free()
				_pile_nodes.erase(zone_name)
		else:
			if node == null:
				node = _main.card_scene.instantiate() as Card
				zone.add_child(node)
				node.position = Vector3.ZERO
				if pid == 1:
					node.rotation.y = PI
				node.back_texture = _main.CARD_BACK
				node.face_down = true
				_pile_nodes[zone_name] = node
